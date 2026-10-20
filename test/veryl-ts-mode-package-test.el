;;; veryl-ts-mode-package-test.el --- Package tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yasushi SHOJI

;; SPDX-License-Identifier: GPL-3.0-or-later

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Install the package in a temporary directory and check its autoloads
;; in fresh Emacs processes.  These tests do not need a grammar.

;;; Code:

(require 'ert)

(defconst veryl-ts-mode-package-test--source
  (expand-file-name "../veryl-ts-mode.el"
                    (file-name-directory (or load-file-name buffer-file-name))))

(defun veryl-ts-mode-package-test--run (directory &rest body)
  "Run BODY in a fresh Emacs process with its configuration in DIRECTORY."
  (with-temp-buffer
    (let ((status
           (call-process
            (expand-file-name invocation-name invocation-directory)
            nil (current-buffer) nil "-Q" "--batch" "--eval"
            (prin1-to-string
             `(progn
                (setq user-emacs-directory ,(file-name-as-directory directory))
                (require 'cl-lib)
                (require 'package)
                (setq package-user-dir ,(expand-file-name "elpa" directory)
                      package-directory-list nil
                      package-quickstart-file
                      ,(expand-file-name "package-quickstart.el" directory)
                      custom-file ,(expand-file-name "custom.el" directory)
                      package-archives nil
                      package-native-compile nil)
                ,@body)))))
      (ert-info ((buffer-string))
        (should (equal status 0))))))

(ert-deftest veryl-ts-mode-package-test-install-and-autoload ()
  (let ((directory (make-temp-file "veryl-ts-mode-package-" t)))
    (unwind-protect
        (progn
          (veryl-ts-mode-package-test--run
           directory
           `(package-install-file ,veryl-ts-mode-package-test--source)
           '(cl-assert (package-installed-p 'veryl-ts-mode)))
          (veryl-ts-mode-package-test--run
           directory
           '(package-initialize)
           '(cl-assert (autoloadp (symbol-function 'veryl-ts-mode)))
           '(cl-assert
             (eq (cdr (assoc "\\.veryl\\'" auto-mode-alist)) 'veryl-ts-mode))
           '(cl-assert (not (featurep 'treesit)))
           '(cl-assert
             (equal (assq 'veryl treesit-language-source-alist)
                    '(veryl "https://github.com/veryl-lang/tree-sitter-veryl")))
           '(require 'treesit)
           '(cl-assert (assq 'veryl treesit-language-source-alist))
           '(cl-assert (not (featurep 'veryl-ts-mode))))
          (dolist (setup '(nil (require 'treesit)))
            (veryl-ts-mode-package-test--run
             directory
             setup
             '(setq treesit-language-source-alist
                    '((veryl "https://example.com/grammar" "revision")))
             '(package-initialize)
             '(require 'treesit)
             '(cl-assert
               (equal (assq 'veryl treesit-language-source-alist)
                      '(veryl "https://example.com/grammar" "revision"))))))
      (delete-directory directory t))))

;;; veryl-ts-mode-package-test.el ends here
