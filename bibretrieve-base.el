;;; bibretrieve-base.el --- Retrieve BibTeX entries from the internet

;; Copyright (C)
;; 2012, 2015 Antonio Sartori
;; 2012, 2013, 2017 Pavel Zorin-Kranich

;; This file is part of BibRetrieve.

;; BibRetrieve is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; BibRetrieve is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with BibRetrieve.  If not, see
;; <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This file contains the code that (with the exception of
;; the function bibretrieve) is not directly exposed to the user.

;; The convenience function "bibretrieve-http" takes as input a URL, queries it,
;; puts the result in a new buffer, and returns this buffer.

;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'reftex)
(require 'reftex-cite)
(require 'reftex-sel)
(require 'mm-url)
(provide 'bibretrieve)

;; Here only to silence the compilator
(defvar bibretrieve-backends)
(defvar bibretrieve-installed-backends)

(defconst bibretrieve-buffer-name-prefix "bibretrieve-results-")

(defun bibretrieve-generate-new-buffer ()
  "Generate and return a new buffer with a bibretrieve-specific name."
  (generate-new-buffer (generate-new-buffer-name bibretrieve-buffer-name-prefix)))

(defun bibretrieve-http (url &optional buffer)
  "Retrieve URL and return the buffer, using mm-url."
  (unless buffer (setq buffer (bibretrieve-generate-new-buffer)))
  (with-current-buffer buffer
    (message "Retrieving %s" url)
    (mm-url-insert-file-contents url))
  buffer)

(defun bibretrieve-backend-msn (query)
  (let* ((pairs `(("bdlback" . "r=1")
		  ("dr" . "all")
		  ("l" . "20")
		  ("pg3" . "ALLF")
		  ("s3" . ,query)
		  ("fn" . "130")
		  ("fmt" . "bibtex")
		  ("bdlall" . "Retrieve+All")))
	 (url (concat "http://www.ams.org/mathscinet/search/publications.html?" (mm-url-encode-www-form-urlencoded pairs)))
	 (buffer (bibretrieve-http url)))
    (with-current-buffer buffer
      (goto-char (point-min))
      (while (re-search-forward "URL = {https://doi.org/" nil t)
	(replace-match "DOI = {"))
      buffer)))

(defun bibretrieve-matches-in-buffer (regexp &optional buffer)
  "Return a list of matches of REGEXP in BUFFER or the current buffer if not given."
  (let ((matches))
    (save-match-data
      (save-excursion
        (with-current-buffer (or buffer (current-buffer))
          (save-restriction
            (widen)
            (goto-char 1)
            (while (search-forward-regexp regexp nil t 1)
              (push (match-string 0) matches)))))
      matches)))

(defun bibretrieve-backend-zbm (query)
  (let* ((url (concat "https://zbmath.org/?" (mm-url-encode-www-form-urlencoded `(("q" . ,query)))))
	 (buffer (bibretrieve-http url))
	 (list-of-bib-urls (bibretrieve-matches-in-buffer "bibtex/[a-zA-Z0-9.]*.bib" buffer))
	 bib-url)
    (with-current-buffer buffer
       (erase-buffer)
      (dolist (bib-url list-of-bib-urls)
	(bibretrieve-http (concat "https://zbmath.org/" bib-url) buffer)
	(goto-char (point-max))
	(insert "\n") ; A bibtex entry may not start on the line on which the previous entry ends
	)
      buffer)))

(defun bibretrieve-backend-ads (query)
  (let* ((pairs `(("qsearch" . ,query)
		  ("data_type" . "BIBTEX"))))
  (bibretrieve-http (concat "http://adsabs.harvard.edu/cgi-bin/basic_connect?" (mm-url-encode-www-form-urlencoded pairs)))))

;; Modified from bibsnarf
(defun bibretrieve-backend-citebase (query)
  (let* ((pairs `(("submitted" . "Search")
		  ("query" . ,query)
		  ("format" . "BibTeX")
		  ("maxrows" . "100")
		  ("order" . "DESC")
		  ("rank" . "1000") ; in what order should we list?
		  )))
    (bibretrieve-http (concat "http://www.citebase.org/search?" (mm-url-encode-www-form-urlencoded pairs)))))

(defun bibretrieve-backend-inspire (query)
  (let* ((pairs `(("q" . ,query)
		  ("format" . "bibtex")
		  ("size" . "1000"))))
  (bibretrieve-http (concat "http://inspirehep.net/api/literature?" (mm-url-encode-www-form-urlencoded pairs)))))

(defun bibretrieve-use-backend (backend query timeout)
  "Call the backend BACKEND with QUERY and TIMEOUT. Return buffer with results."
  (let* ((function-backend (intern (concat "bibretrieve-backend-" backend))))
    (if (functionp function-backend)
	(with-timeout (timeout) (funcall function-backend query))
      (message (concat "Backend " backend " is not defined.")))))

(defun bibretrieve-extract-bib-entries (buffers)
  "Extract all bib entries from BUFFERS.
BUFFERS is a list of buffers or file names.
Return list with entries."
  (flet ((reftex--query-search-regexps (default) nil) ; Do not ask for a REGEXP
	 (reftex-get-bibkey-default () "=")) ; Match all bib entries
    (reftex-extract-bib-entries buffers)))

(defun bibretrieve-retrieve (query backends &optional newtimeout)
  "Search QUERY on BACKENDS.
If NEWTIMEOUT is given, this replaces the timeout for all backends.
Return list with entries."
  (let (buffers buffer found-list)
    (dolist (backend backends)
      (let* ((timeout (or (or newtimeout (cdr (assoc backend bibretrieve-backends))) "0"))
	     (buffer (bibretrieve-use-backend backend query timeout)))
	(if (bufferp buffer)
	    (add-to-list 'buffers buffer)
	  (message (concat "Backend " backend " failed.")))))
    (setq found-list (bibretrieve-extract-bib-entries buffers))
    found-list))

(defvar bibretrieve-author-history nil)
(defun bibretrieve-prompt-and-retrieve (&optional arg)
  "Prompt for query and retrieve.
If the optional argument ARG is an integer
then it is used as the timeout (in seconds).
If the optional argument ARG is non-nil and not integer,
prompt for the backends to use and the timeout.
Return list with entries."
  (let* (query backend backends timeout)
    (when arg
      (if (integerp arg)
	  (setq timeout arg)
	(progn (setq backend (completing-read "Backend to use: [defaults] " (append bibretrieve-installed-backends '("DEFAULTS" "ALL")) nil t nil nil "DEFAULTS"))
	       (setq timeout (read-number "Timeout (seconds) " 5)))))
    (setq backends
	  (cond ((or (not backend) (equal backend "DEFAULTS"))
		 (mapcar 'car bibretrieve-backends))
		((equal backend "ALL")
		 'bibretrieve-installed-backends)
		(t
		 `(,backend))))
    (setq query (read-string "Query: "))
    (bibretrieve-retrieve query backends timeout))
  )

(defun bibretrieve-find-bibliography-file ()
  "Try to find a bibliography file using RefTeX."
  ;; Returns a string with text properties (as expected by read-file-name)
  ;; or empty string if no file can be found
  (let ((bibretrieve-bibfile-list nil))
    (condition-case nil
	(setq bibretrieve-bibfile-list (reftex-get-bibfile-list))
      (error (ignore-errors
	       (setq bibretrieve-bibfile-list (reftex-default-bibliography))))
      )
    (if bibretrieve-bibfile-list
	(car bibretrieve-bibfile-list) "")
    )
  )

(defun bibretrieve-find-default-bibliography-file ()
   "Find a default bibliography file to write entries in.
Try with a \bibliography in the current buffer
or if the current buffer is a bib buffer,
else return nil."
  (or (bibretrieve-find-bibliography-file)
      (if buffer-file-name
	  (and (string-match ".*\\.bib$" buffer-file-name)
	       (buffer-file-name)))))

;; Copied from RefTeX
;; Limit FOUND-LIST with more regular expressions
;; Returns a string with all matching bibliography items
(defun bibretrieve-extract-bib-items (all &optional marked complement)
    (setq all (delq nil
                    (mapcar
                     (lambda (x)
                       (if marked
                           (if (or (and (assoc x marked) (not complement))
                                   (and (not (assoc x marked)) complement))
                               (cdr (assoc "&entry" x))
                             nil)
                         (cdr (assoc "&entry" x))))
                     all)))
    (mapconcat 'identity all "\n\n")
    )

(defun bibretrieve-write-bib-items-bibliography (all bibfile marked complement)
  "Append item to file.

From ALL, append to a prompted file (BIBFILE is the default one) MARKED entries (or unmarked, if COMPLEMENT is t)."
  (let ((file (read-file-name (if bibfile (concat "Bibfile: [" bibfile "] ") "Bibfile: ") default-directory bibfile)))
    (if (find-file-other-window file)
	(save-excursion
	  (goto-char (point-max))
	  (insert "\n")
	  (insert (bibretrieve-extract-bib-items all marked complement))
	  (insert "\n")
	  (save-buffer)
	  file
	  )
      (error "Invalid file"))))

;; Callback function to be called from the bibliography selection, in
;; order to display context.
(defun bibretrieve-selection-callback (data ignore no-revisit)
  (let ((win (selected-window))
;        (key (reftex-get-bib-field "&key" data))
;        bibfile-list item bibtype)
	(origin (buffer-name)))
    (pop-to-buffer "*BibRetrieve Record*")
    (setq buffer-read-only nil)
    (erase-buffer)
    (bibtex-mode)
    (goto-char (point-min))
    (insert (reftex-get-bib-field "&entry" data))
    ;;    (shrink-window-if-larger-than-buffer)  ; FIXME: this needs to be recalibrated for each record
    (goto-char (point-min))
    (setq buffer-read-only t)
    (pop-to-buffer origin)
    )
  )

;; Prompt and help string for citation selection
(defconst bibretrieve-select-prompt
  "Select: [n]ext [p]revious a[g]ain [r]efine [f]ull_entry [q]uit RET [?]Help+more")

;; Adapted from RefTeX
(defconst bibretrieve-select-help
  " n / p      Go to next/previous entry (Cursor motion works as well).
 g / r      Start over with new search / Refine with additional regexp.
 SPC        Show full database entry in other window.
 f          Toggle follow mode: Other window will follow with full db entry.
 .          Show current append point.
 q          Quit.
 TAB        Enter citation key with completion.
 RET        Accept current entry (also on mouse-2), and append it to default BibTeX file.
 m / u      Mark/Unmark the entry.
 e / E      Append all (marked/unmarked) entries to default BibTeX file.
 a / A      Put all (marked) entries into current buffer.")

;; Modified version of reftex-offer-bib-menu
(defun bibretrieve-offer-bib-menu (&optional arg)
  "Offer bib menu and return list of selected items.
ARG is the optional argument."

  (let ((bibfile (bibretrieve-find-default-bibliography-file))
        found-list rtn key data selected-entries)
    (while
        (not
         (catch 'done
           ;; Retrieve and scan entries
	   (setq found-list (bibretrieve-prompt-and-retrieve arg))

           (unless found-list
             (error "No matches found"))

          ;; Remember where we came from
          (setq reftex-call-back-to-this-buffer (current-buffer))
          (set-marker reftex-select-return-marker (point))

          ;; Offer selection
          (save-window-excursion
            (delete-other-windows)
            (let ((major-mode 'reftex-select-bib-mode))
              (reftex-kill-buffer "*RefTeX Select*")
              (switch-to-buffer-other-window "*RefTeX Select*")
              (unless (eq major-mode 'reftex-select-bib-mode)
                (reftex-select-bib-mode))
              (let ((buffer-read-only nil))
                (erase-buffer)
                (reftex-insert-bib-matches found-list)))
            (setq buffer-read-only t)
            (if (= 0 (buffer-size))
                (error "No matches found"))
            (setq truncate-lines t)
            (goto-char 1)
            (while t
              (setq rtn
                    (reftex-select-item
                     bibretrieve-select-prompt
                     bibretrieve-select-help
                     reftex-select-bib-mode-map
                     nil
                     'bibretrieve-selection-callback nil))
              (setq key (car rtn)
                    data (nth 1 rtn))
              (unless key (throw 'done t))
              (cond
               ((eq key ?g)
                ;; Start over
                (throw 'done nil))
               ((eq key ?r)
                ;; Restrict with new regular expression
                (setq found-list (reftex-restrict-bib-matches found-list))
                (let ((buffer-read-only nil))
                  (erase-buffer)
                  (reftex-insert-bib-matches found-list))
                (goto-char 1))
               ((eq key ?A)
                ;; Take all
                (setq selected-entries found-list)
                (throw 'done t))
               ((eq key ?a)
                ;; Take all marked
		;; If nothing is marked, then mark current selection
		(if (not reftex-select-marked)
		    (reftex-select-mark))
                (setq selected-entries (mapcar 'car (nreverse reftex-select-marked)))
                (throw 'done t))
               ((eq key ?e)
                ;; Take all marked and append them
                (let ((file (bibretrieve-write-bib-items-bibliography found-list bibfile reftex-select-marked nil)))
		  (when file
		    (setq selected-entries
			  (concat "BibTeX entries appended to " file))
		    (throw 'done t)))
		(message "File not found, nothing done"))
               ((eq key ?E)
                ;; Take all unmarked and append them
                (let ((file (bibretrieve-write-bib-items-bibliography found-list bibfile reftex-select-marked 'complement)))
		  (when file
		    (setq selected-entries
			  (concat "BibTeX entries appended to " file))
		    (throw 'done t)))
		(message "File not found, nothing done"))
               ((or (eq key ?\C-m)
                    (eq key 'return))
                ;; Take selected
		;; If nothing is marked, then mark current selection
		(let ((marked reftex-select-marked))
		    (unless marked (reftex-select-mark))
		    (let ((file (bibretrieve-write-bib-items-bibliography found-list bibfile reftex-select-marked nil)))
		      (when file
			(setq selected-entries (concat "BibTeX entries appended to " file))
			(throw 'done t)))
		    (unless marked (reftex-select-unmark)))
		(message "File not found, nothing done. Press q to exit."))
               ((stringp key)
                ;; Got this one with completion
                (setq selected-entries key)
                (throw 'done t))
               (t
                (ding))))))))
    selected-entries))


;; Get records from the web and insert them in the bibliography

;; Adapted from RefTeX
;;;###autoload
(defun bibretrieve ()
  "Search the web for bibliography entries.

After prompting for query, searches on the web, using the
backends specified by the customization variable
`bibretrieve-backends'.  A selection process (using RefTeX Selection)
allows to select entries to add to the current buffer or to a
bibliography file.

When called with a `C-u' prefix, permits to select the backend and the
timeout for the search."

  (interactive)

  ;; check for recursive edit
  (reftex-check-recursive-edit)

  ;; This function may also be called outside reftex-mode.
  ;; Thus look for the scanning info only if in reftex-mode.

  (when reftex-mode
    (reftex-access-scan-info nil))

  ;; Call bibretrieve-do-retrieve, but protected
  (unwind-protect
      (bibretrieve-do-retrieve current-prefix-arg)
    (progn
      (reftex-kill-temporary-buffers)
      (reftex-kill-buffer "*BibRetrieve Record*")
      (reftex-kill-buffer "*RefTeX Select*")
      (kill-matching-buffers (concat "^" bibretrieve-buffer-name-prefix) nil t))))

;; Adapted from RefTeX
(defun bibretrieve-do-retrieve (&optional arg)
  "This really does the work of bibretrieve.
ARG is the optional argument."

  (let ((selected-entries (bibretrieve-offer-bib-menu arg)))

    (set-marker reftex-select-return-marker nil)

    (if (stringp selected-entries)
      (message selected-entries)
      (if (not selected-entries)
	  (message "Quit")
 	(insert (bibretrieve-extract-bib-items selected-entries))
	)
      )
    ))

(provide 'bibretrieve-base)

;;; bibretrieve-base.el ends here
