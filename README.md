This is the README file for Leo's fork of BibRetrieve.

Requirements
------------

*AUCTeX 11.87* is needed to run the current version of `bibretrieve`.

Installation
------------

* Clone the repository:

```sh
mkdir -p ~/.emacs.d
cd ~/.emacs.d
git clone git://github.com/pzorin/bibretrieve.git
```

* Add instructions e.g. to `init.el` to load BibRetrieve:

```lisp
(add-to-list 'load-path "~/.emacs.d/bibretrieve")
; Recompile if .el is newer than .elc
(byte-recompile-directory "~/.emacs.d/bibretrieve" 0)
(load "bibretrieve")
```

Usage
-----

`M-x bibretrieve` or `C-u M-x bibretrieve`.

Configuration
-------------

BibRetrieve can be configured with `customize`, but it is probably easier to edit e.g. `init.el` directly.

To configure the backends used, set the variable `bibretrieve-backends`.
This is an alist with the names of the backends as keys and the timeouts as values.
The default configuration is:

```lisp
(setq bibretrieve-backends '(("mrl" . 10) ("arxiv" . 5) ("zbm" . 5)))
```

The following backends are included in the repository.

Backend | Key
--------|----
[ArXiv](http://adsabs.harvard.edu) | "arxiv"
[MathSciNet](http://www.ams.org/mathscinet) | "msn"
[MrLookup](http://www.ams.org/mrlookup) | "mrl"
[Citebase](http://www.citebase.org) | "citebase"
[Inspire](http://inspirehep.net) | "inspire"
[Zentralblatt MATH](http://www.zentralblatt-math.org/zmath) | "zbm"

If you want to add a backend, read the Commentary section in the source file `bibretrieve.el`.

Network requests are handled by `mm-url`, by default this uses the library `url`.
If you want to use an external program, like `wget` or `curl`, put it in the variable `mm-url-program` and set the variable `mm-url-use-external` to `t`.

Acknowledgments
---------------

This program has been inspired by [bibsnarf](http://www.princeton.edu/~hhalvors/tools/bibsnarf.el).
The functions that create the urls for most backends are taken from there.

This programs also uses lot of function of *RefTeX*.
The selection process is entirely based on `reftex-sel`.
Many function have also been adapted from there.
