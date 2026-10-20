;;; veryl-ts-mode.el --- Major mode for Veryl using tree-sitter -*- lexical-binding: t; -*-

;; Author: Yasushi SHOJI <yashi@spacecubics.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: languages
;; URL: https://github.com/yashi/veryl-ts-mode

;;; Commentary:

;; Edit Veryl source with tree-sitter highlighting, indentation, Imenu,
;; and definition navigation.  Install the grammar with
;; M-x treesit-install-language-grammar RET veryl RET.

;;; Code:

(require 'treesit)
(require 'seq)
(eval-when-compile (require 'rx))

(defgroup veryl-ts nil
  "Editing Veryl source."
  :group 'languages
  :prefix "veryl-ts-mode-")

(defcustom veryl-ts-mode-indent-offset 4
  "Number of spaces per indentation level."
  :type 'natnum
  :safe 'natnump
  :group 'veryl-ts)

(defvar veryl-ts-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?_ "_" table)
    (modify-syntax-entry ?$ "_" table)
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\\ "\\" table)
    (modify-syntax-entry ?/ ". 124b" table)
    (modify-syntax-entry ?* ". 23" table)
    (modify-syntax-entry ?\n "> b" table)
    (modify-syntax-entry ?\r "> b" table)
    (dolist (char '(?+ ?- ?= ?% ?& ?| ?^ ?! ?~ ?< ?> ?' ?` ?# ?:))
      (modify-syntax-entry char "." table))
    table)
  "Syntax table for `veryl-ts-mode'.")

(defconst veryl-ts-mode--definition-regexp
  (rx string-start
      (or "module_declaration" "interface_declaration" "package_declaration"
          "function_declaration" "struct_declaration" "enum_declaration"
          "type_declaration" "modport_declaration")
      string-end)
  "Node types used for definition navigation.")

(defconst veryl-ts-mode--keywords
  '("module" "interface" "package" "function" "struct" "enum" "type"
    "const" "var" "let" "param" "modport" "inst" "generate" "import"
    "embed" "always_comb" "always_ff" "initial" "assign" "if" "else"
    "if_reset" "for" "in" "rev" "step" "case" "switch" "default"
    "break" "return" "repeat" "as" "input" "output" "inout" "ref"
    "signed" "tri")
  "Keywords recognized by the Veryl grammar.")

(defun veryl-ts-mode--font-lock-settings ()
  "Build font-lock rules after the Veryl grammar is available."
  (treesit-font-lock-rules
   :language 'veryl
   :feature 'comment
   '(((line_comment) @font-lock-doc-face
      (:match "\\`///" @font-lock-doc-face))
     [(line_comment) (block_comment)] @font-lock-comment-face)

   :language 'veryl
   :feature 'string
   '([(string_literal) (embed_content)] @font-lock-string-face)

   :language 'veryl
   :feature 'definition
   '((module_declaration (identifier) @font-lock-type-face)
     (interface_declaration (identifier) @font-lock-type-face)
     (package_declaration (identifier) @font-lock-type-face)
     (struct_declaration (identifier) @font-lock-type-face)
     (enum_declaration (identifier) @font-lock-type-face)
     (type_declaration :anchor (identifier) @font-lock-type-face)
     (modport_declaration :anchor (identifier) @font-lock-type-face)
     (function_declaration "function" :anchor
                           (identifier) @font-lock-function-name-face)
     (variable_declaration :anchor (identifier) @font-lock-variable-name-face)
     (port_declaration :anchor (identifier) @font-lock-variable-name-face)
     (function_parameter :anchor (identifier) @font-lock-variable-name-face)
     (parameter_declaration :anchor (identifier) @font-lock-constant-face)
     (const_declaration :anchor (identifier) @font-lock-constant-face)
     (enum_member :anchor (identifier) @font-lock-constant-face)
     (instance :anchor (identifier) @font-lock-variable-name-face)
     (for_statement :anchor (identifier) @font-lock-variable-name-face))

   :language 'veryl
   :feature 'keyword
   `([,@veryl-ts-mode--keywords] @font-lock-keyword-face)

   :language 'veryl
   :feature 'type
   '(["logic" "bit" "bbool" "lbool" "u32" "u64" "i32"
      "clock" "reset" "string"] @font-lock-type-face
     (variable_declaration ":" :anchor [(identifier) (scoped_identifier)]
                           @font-lock-type-face)
     (const_declaration ":" :anchor [(identifier) (scoped_identifier)]
                        @font-lock-type-face)
     (parameter_declaration ":" :anchor [(identifier) (scoped_identifier)]
                            @font-lock-type-face)
     (struct_field ":" :anchor [(identifier) (scoped_identifier)]
                   @font-lock-type-face)
     (function_parameter ":" :anchor [(identifier) (scoped_identifier)]
                         @font-lock-type-face)
     (function_parameter ["input" "output" "inout" "ref"]
                         :anchor [(identifier) (scoped_identifier)]
                         @font-lock-type-face)
     (port_declaration (port_direction) :anchor
                       [(identifier) (scoped_identifier)]
                       @font-lock-type-face)
     (port_declaration "modport" :anchor
                       (scoped_identifier) @font-lock-type-face)
     (function_declaration "->" :anchor [(identifier) (scoped_identifier)]
                           @font-lock-type-face)
     (type_declaration "=" :anchor [(identifier) (scoped_identifier)]
                       @font-lock-type-face)
     (enum_declaration ":" :anchor [(identifier) (scoped_identifier)]
                       @font-lock-type-face)
     (for_statement ":" :anchor [(identifier) (scoped_identifier)]
                    @font-lock-type-face)
     (cast_expression "as" :anchor [(identifier) (scoped_identifier)]
                      @font-lock-type-face)
     (instance (scoped_identifier) @font-lock-type-face))

   :language 'veryl
   :feature 'constant
   '([(boolean_literal) (special_literal)] @font-lock-constant-face)

   :language 'veryl
   :feature 'number
   '((number_literal) @font-lock-number-face)

   :language 'veryl
   :feature 'attribute
   '((attribute :anchor (identifier) @font-lock-preprocessor-face))

   :language 'veryl
   :feature 'builtin
   '([(system_function_identifier) (scoped_system_function_identifier)]
     @font-lock-builtin-face)

   :language 'veryl
   :feature 'function
   '((call_expression :anchor (identifier) @font-lock-function-call-face)
     (call_expression :anchor
                      (scoped_identifier
                       (identifier) @font-lock-function-call-face :anchor)))

   :language 'veryl
   :feature 'property
   '((struct_field :anchor (identifier) @font-lock-property-name-face)
     (struct_field_init :anchor (identifier) @font-lock-property-use-face)
     (instance_parameter :anchor (identifier) @font-lock-property-use-face)
     (instance_port :anchor (identifier) @font-lock-property-use-face)
     (member_expression "." (identifier) @font-lock-property-use-face))

   :language 'veryl
   :feature 'operator
   '(["=" "+=" "-=" "*=" "/=" "%=" "&=" "|=" "^=" "<<=" ">>="
      "<<<=" ">>>=" "+" "-" "*" "/" "%" "**" "&" "|" "^" "~"
      "~&" "~|" "~^" "!" "&&" "||" "<<" ">>" "<<<" ">>>"
      "<:" "<=" ">:" ">=" "==" "!=" "==?" "!=?" ".." "..=" "::" "->"]
     @font-lock-operator-face)

   :language 'veryl
   :feature 'bracket
   '(["(" ")" "[" "]" "{" "}" "<" ">"] @font-lock-bracket-face)

   :language 'veryl
   :feature 'delimiter
   '([":" ";" "," "."] @font-lock-delimiter-face)

   :language 'veryl
   :feature 'variable
   '((identifier) @font-lock-variable-use-face)))

(defun veryl-ts-mode--comment-star-p (_node _parent bol)
  "Return non-nil for a comment line with a leading star at BOL."
  (save-excursion
    (goto-char bol)
    (looking-at-p "\\*")))

(defun veryl-ts-mode--expression-anchor (_node parent _bol)
  "Return the indentation position before PARENT's expression chain."
  (while (and (treesit-node-parent parent)
              (string-match-p
               "\\`\\(?:binary\\|unary\\|range\\|member\\|cast\\)_expression\\'"
               (treesit-node-type parent)))
    (setq parent (treesit-node-parent parent)))
  (save-excursion
    (goto-char (treesit-node-start parent))
    (back-to-indentation)
    (point)))

(defvar veryl-ts-mode--indent-rules
  `((veryl
     ((parent-is "\\`\\(?:embed_content\\|string_literal\\)\\'") no-indent 0)
     ((and (parent-is "block_comment") veryl-ts-mode--comment-star-p)
      parent 1)
     ((parent-is "block_comment") prev-adaptive-prefix 0)
     ((parent-is "source_file") column-0 0)
     ((node-is "\\`[])}>]\\'") parent-bol 0)
     ((node-is "\\`[{(]\\'") parent-bol 0)
     ((node-is
       ,(rx string-start
            (or "module" "interface" "package" "function" "struct" "enum"
                "block" "parameter_list" "port_list" "function_parameter_list"
                "instance_parameter_list" "instance_port_list")
            string-end))
      parent-bol 0)
     ((parent-is
       ,(rx string-start
            (or "module_declaration" "interface_declaration"
                "package_declaration" "struct_declaration" "enum_declaration"
                "modport_declaration" "block" "case_statement" "case_expression"
                "switch_statement" "case_arm" "default_case_arm"
                "switch_arm" "default_switch_arm"
                "parameter_list" "port_list" "function_parameter_list"
                "instance_parameter_list" "instance_port_list"
                "call_expression" "parenthesized_expression"
                "packed_dimension" "unpacked_dimension" "index_expression"
                "concatenation" "struct_literal" "attribute")
            string-end))
      parent-bol veryl-ts-mode-indent-offset)
     ((parent-is
       ,(rx string-start
            (or "variable_declaration" "const_declaration"
                "parameter_declaration" "assign_statement"
                "assignment_statement" "return_statement"
                "binary_expression" "unary_expression" "range_expression"
                "member_expression" "cast_expression" "if_statement"
                "if_expression" "for_statement" "function_declaration"
                "instance" "struct_field_init" "instance_port"
                "instance_parameter")
            string-end))
      veryl-ts-mode--expression-anchor veryl-ts-mode-indent-offset)
     (catch-all parent-bol 0)))
  "Tree-sitter indentation rules for Veryl.")

(defun veryl-ts-mode--defun-name (node)
  "Return the name of the declaration at NODE."
  (treesit-node-text
   (seq-find (lambda (child)
               (equal (treesit-node-type child) "identifier"))
             (treesit-node-children node t))
   t))

;;;###autoload
(define-derived-mode veryl-ts-mode prog-mode "Veryl"
  "Major mode for editing Veryl with tree-sitter.

Install the grammar with `treesit-install-language-grammar'.
Customize indentation with `veryl-ts-mode-indent-offset'."
  :group 'veryl-ts
  :syntax-table veryl-ts-mode-syntax-table
  (unless (treesit-ready-p 'veryl t)
    (user-error
     (concat "Veryl needs tree-sitter support and a compatible grammar. "
             "Run M-x treesit-install-language-grammar RET veryl")))
  (treesit-parser-create 'veryl)
  (setq-local comment-start "// "
              comment-end ""
              comment-start-skip "\\(?://+\\|/\\*+\\)\\s-*"
              comment-end-skip "\\s-*\\(?:\\*+/\\|$\\)"
              comment-multi-line t
              indent-tabs-mode nil
              treesit-simple-indent-rules veryl-ts-mode--indent-rules
              treesit-font-lock-settings (veryl-ts-mode--font-lock-settings)
              treesit-font-lock-feature-list
              '((comment definition)
                (keyword string type)
                (attribute builtin constant function number property)
                (bracket delimiter operator variable))
              treesit-defun-type-regexp veryl-ts-mode--definition-regexp
              treesit-defun-name-function #'veryl-ts-mode--defun-name
              treesit-simple-imenu-settings
              '(("Modules" "\\`module_declaration\\'" nil nil)
                ("Interfaces" "\\`interface_declaration\\'" nil nil)
                ("Packages" "\\`package_declaration\\'" nil nil)
                ("Functions" "\\`function_declaration\\'" nil nil)
                ("Structs" "\\`struct_declaration\\'" nil nil)
                ("Enums" "\\`enum_declaration\\'" nil nil)
                ("Types" "\\`type_declaration\\'" nil nil)
                ("Modports" "\\`modport_declaration\\'" nil nil)))
  (setq-local electric-indent-chars
              (append "{}()[];:," electric-indent-chars))
  (treesit-major-mode-setup))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.veryl\\'" . veryl-ts-mode))

(unless (assq 'veryl treesit-language-source-alist)
  (add-to-list 'treesit-language-source-alist
               '(veryl "https://github.com/veryl-lang/tree-sitter-veryl")))

(provide 'veryl-ts-mode)

;;; veryl-ts-mode.el ends here
