;;; veryl-ts-mode-test.el --- Tests for Veryl mode -*- lexical-binding: t; -*-

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

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'imenu)
(require 'veryl-ts-mode)

(defconst veryl-ts-mode-test--directory
  (file-name-directory (or load-file-name buffer-file-name)))

(when-let ((directory (getenv "VERYL_TS_MODE_GRAMMAR_DIR")))
  (unless (equal directory "")
    (add-to-list 'treesit-extra-load-path directory)))

(defmacro veryl-ts-mode-test--with-buffer (text &rest body)
  "Insert TEXT, enable Veryl mode, and evaluate BODY."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert ,text)
     (veryl-ts-mode)
     (goto-char (point-min))
     ,@body))

(defun veryl-ts-mode-test--fixture ()
  "Read the indentation fixture."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "fixtures/sample.veryl" veryl-ts-mode-test--directory))
    (buffer-string)))

(defun veryl-ts-mode-test--face (text &optional offset)
  "Return the face at OFFSET within the first occurrence of TEXT."
  (save-excursion
    (let ((case-fold-search nil))
      (goto-char (point-min))
      (search-forward text)
      (get-text-property (+ (- (point) (length text)) (or offset 0)) 'face))))

(defun veryl-ts-mode-test--check-indent (expected)
  "Check indentation of EXPECTED after removing its leading whitespace."
  (veryl-ts-mode-test--with-buffer
      (replace-regexp-in-string "^[ \t]+" "" expected)
    (should-not (treesit-node-check (treesit-buffer-root-node) 'has-error))
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string) expected))
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string) expected))))

(ert-deftest veryl-ts-mode-test-grammar-available ()
  (should (treesit-ready-p 'veryl t)))

(ert-deftest veryl-ts-mode-test-activation ()
  (veryl-ts-mode-test--with-buffer "module Sample {}\n"
    (should (derived-mode-p 'prog-mode))
    (should (eq major-mode 'veryl-ts-mode))
    (should (equal (mapcar #'treesit-parser-language (treesit-parser-list))
                   '(veryl)))
    (should (eq indent-line-function #'treesit-indent))
    (should-not indent-tabs-mode)
    (veryl-ts-mode)
    (should (= (length (treesit-parser-list)) 1))))

(ert-deftest veryl-ts-mode-test-file-association ()
  (with-temp-buffer
    (setq buffer-file-name "/tmp/sample.veryl")
    (set-auto-mode)
    (should (eq major-mode 'veryl-ts-mode))))

(ert-deftest veryl-ts-mode-test-missing-grammar ()
  (cl-letf (((symbol-function 'treesit-ready-p) (lambda (&rest _) nil)))
    (with-temp-buffer
      (let ((error (should-error (veryl-ts-mode) :type 'user-error)))
        (should (string-match-p "treesit-install-language-grammar"
                                (error-message-string error)))))))

(ert-deftest veryl-ts-mode-test-preserve-grammar-recipe ()
  (let* ((recipe '(veryl "https://example.com/grammar" "revision"))
         (treesit-language-source-alist (list recipe)))
    (load (expand-file-name "../veryl-ts-mode.el"
                            veryl-ts-mode-test--directory)
          nil t)
    (should (equal (assq 'veryl treesit-language-source-alist) recipe))))

(ert-deftest veryl-ts-mode-test-font-lock ()
  (let ((treesit-font-lock-level 4))
    (veryl-ts-mode-test--with-buffer (veryl-ts-mode-test--fixture)
      (font-lock-ensure)
      (dolist (check '(("/// Counts" font-lock-doc-face)
                       ("// Print" font-lock-comment-face)
                       ("module Counter" font-lock-keyword-face)
                       ("Counter" font-lock-type-face)
                       ("increment" font-lock-function-name-face)
                       ("word_t" font-lock-type-face)
                       ("logic" font-lock-type-face)
                       ("WIDTH" font-lock-constant-face)
                       ("clk:" font-lock-variable-name-face)
                       ("value: input" font-lock-variable-name-face)
                       ("LIMIT" font-lock-constant-face)
                       ("Idle" font-lock-constant-face)
                       ("low:" font-lock-property-name-face)
                       ("test(counter)" font-lock-preprocessor-face)
                       ("true" font-lock-constant-face)
                       ("8'hff" font-lock-number-face)
                       ("'0" font-lock-constant-face)
                       ("$display" font-lock-builtin-face)
                       ("\"count = %d\"" font-lock-string-face)
                       ("+=" font-lock-operator-face)
                       ("{{{" font-lock-string-face)))
        (ert-info ((car check))
          (should (eq (veryl-ts-mode-test--face (car check)) (cadr check)))))
      (should (eq (veryl-ts-mode-test--face "logic<WIDTH>" 6)
                  'font-lock-variable-use-face))
      (should (eq (veryl-ts-mode-test--face "types::increment(" 7)
                  'font-lock-function-call-face))
      (should (eq (veryl-ts-mode-test--face "high: value" 6)
                  'font-lock-variable-use-face)))))

(ert-deftest veryl-ts-mode-test-type-and-name-faces ()
  (let ((treesit-font-lock-level 4))
    (veryl-ts-mode-test--with-buffer
        "function copy (value: input word_t) -> word_t {
    return value;
}
module Sample {
    let result: word_t = copy(data);
    const LIMIT: word_t = result;
}
"
      (font-lock-ensure)
      (dolist (check '(("copy (" 0 font-lock-function-name-face)
                       ("-> word_t" 3 font-lock-type-face)
                       ("input word_t" 6 font-lock-type-face)
                       ("let result" 4 font-lock-variable-name-face)
                       ("result: word_t" 8 font-lock-type-face)
                       ("= copy" 2 font-lock-function-call-face)
                       ("copy(data)" 5 font-lock-variable-use-face)
                       ("= result" 2 font-lock-variable-use-face)))
        (ert-info ((car check))
          (should (eq (veryl-ts-mode-test--face (nth 0 check) (nth 1 check))
                      (nth 2 check))))))))

(ert-deftest veryl-ts-mode-test-indent-fixture ()
  (let* ((fixture (veryl-ts-mode-test--fixture))
         (code (substring fixture 0 (string-match "embed " fixture))))
    (veryl-ts-mode-test--check-indent code)))

(ert-deftest veryl-ts-mode-test-indent-offset ()
  (let ((veryl-ts-mode-indent-offset 2))
    (veryl-ts-mode-test--check-indent
     "module Sample (
  clk: input clock,
) {
  always_ff (clk) {
    if_reset {
      value = 0;
    }
  }
}
")))

(ert-deftest veryl-ts-mode-test-indent-continuations ()
  (veryl-ts-mode-test--check-indent
   "module Sample {
    let result: logic<8> =
        first +
        second +
        third;
    assign result =
        compute(
            first,
            second,
        );
}
"))

(ert-deftest veryl-ts-mode-test-indent-separate-delimiters ()
  (veryl-ts-mode-test--check-indent
   "module Sample
(
    clk: input clock,
)
{
    function sample
    (
        value: input u32,
    ) -> u32
    {
        if value == 0
        {
            return 1;
        }
        return value;
    }
}
"))

(ert-deftest veryl-ts-mode-test-indent-comments ()
  (veryl-ts-mode-test--check-indent
   "module Sample {
    /* Count cycles.
     * Stop at the limit.
     */
    var count: u32;
    // Reset the count.
    always_ff {
        count = 0;
    }
}
"))

(ert-deftest veryl-ts-mode-test-preserve-embedded-content ()
  (let ((source "embed (inline) sv{{{
    module helper;
      initial $display(\"ready\");
    endmodule
}}}
"))
    (veryl-ts-mode-test--with-buffer source
      (indent-region (point-min) (point-max))
      (should (equal (buffer-string) source)))))

(ert-deftest veryl-ts-mode-test-indent-empty-line ()
  (veryl-ts-mode-test--with-buffer "module Sample {\n\n}\n"
    (forward-line 1)
    (indent-according-to-mode)
    (should (= (current-indentation) 4))))

(ert-deftest veryl-ts-mode-test-comment-syntax ()
  (veryl-ts-mode-test--with-buffer
      "module Sample {
    var count: logic<8> = 8'hff;
    // count
    /* count */
    initial { $display(\"// text\"); }
}
"
    (search-forward "8'hff")
    (should-not (nth 3 (syntax-ppss)))
    (should-not (nth 4 (syntax-ppss)))
    (search-forward "// count")
    (should (nth 4 (syntax-ppss)))
    (search-forward "/* count")
    (should (nth 4 (syntax-ppss)))
    (search-forward "// text")
    (should (nth 3 (syntax-ppss)))
    (should-not (nth 4 (syntax-ppss)))))

(ert-deftest veryl-ts-mode-test-comment-region ()
  (veryl-ts-mode-test--with-buffer "module Sample {}\n"
    (comment-region (point-min) (point-max))
    (should (equal (buffer-string) "// module Sample {}\n"))
    (uncomment-region (point-min) (point-max))
    (should (equal (buffer-string) "module Sample {}\n"))))

(ert-deftest veryl-ts-mode-test-imenu ()
  (veryl-ts-mode-test--with-buffer (veryl-ts-mode-test--fixture)
    (let ((index (funcall imenu-create-index-function)))
      (dolist (entry '(("Modules" "Counter")
                       ("Interfaces" "Link")
                       ("Packages" "types")
                       ("Functions" "increment")
                       ("Structs" "Pair")
                       ("Enums" "Phase")
                       ("Types" "word_t")
                       ("Modports" "source")))
        (let ((position (cdr (assoc (cadr entry)
                                    (cdr (assoc (car entry) index))))))
          (should (markerp position))
          (should (equal (veryl-ts-mode--defun-name
                          (treesit-parent-until
                           (treesit-node-at (marker-position position) 'veryl)
                           (lambda (node)
                             (string-match-p veryl-ts-mode--definition-regexp
                                             (treesit-node-type node)))))
                         (cadr entry))))))))

(ert-deftest veryl-ts-mode-test-defun-navigation ()
  (veryl-ts-mode-test--with-buffer
      "module First {}\nmodule Second {}\n"
    (goto-char (point-max))
    (beginning-of-defun)
    (should (looking-at-p "module Second"))
    (beginning-of-defun)
    (should (looking-at-p "module First"))
    (end-of-defun)
    (should (= (line-number-at-pos) 2))))

(ert-deftest veryl-ts-mode-test-incomplete-source ()
  (dolist (source '("" "module" "module Sample {\n"
                    "module Sample {\n    always_ff {\n        value =\n"
                    "module Sample {\n    var value: logic<"))
    (veryl-ts-mode-test--with-buffer source
      (font-lock-ensure)
      (indent-region (point-min) (point-max))
      (funcall imenu-create-index-function))))

(provide 'veryl-ts-mode-test)

;;; veryl-ts-mode-test.el ends here
