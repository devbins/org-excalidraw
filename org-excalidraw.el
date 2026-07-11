;;; org-excalidraw.el --- Display Excalidraw drawings in org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: devbin
;; Version: 0.1.0
;; Package-Requires: ((emacs "31"))
;; Keywords: org, excalidraw, drawing, diagrams
;; URL: https://github.com/devbins/org-excalidraw

;;; Commentary:

;; This package allows creating, editing, and displaying Excalidraw drawings
;; inline in org-mode buffers. It uses kroki-cli for SVG export and supports
;; both HTML and LaTeX export.
;;
;; Requirements:
;; - Emacs 31+ (native SVG support via librsvg)
;; - kroki-cli (https://github.com/yuzutech/kroki-cli)

;;; Code:

(require 'org)
(require 'json)
(require 'subr-x)

;;; Customization

(defgroup org-excalidraw nil
  "Options for org-excalidraw."
  :group 'org
  :prefix "org-excalidraw-")

(defcustom org-excalidraw-converter-executable "kroki"
  "Path to the converter executable (e.g. kroki-cli)."
  :type 'string
  :group 'org-excalidraw)

(defcustom org-excalidraw-default-width 600
  "Default display width in pixels."
  :type 'integer
  :group 'org-excalidraw)

;;; Excalidraw File Template

(defun org-excalidraw--create-template ()
  "Return a minimal valid Excalidraw JSON structure."
  '((type . "excalidraw")
    (version . 2)
    (source . "https://excalidraw.com")
    (elements)
    (appState (gridSize) (viewBackgroundColor . "#ffffff"))
    (files)))

;;; Core Functions

(defun org-excalidraw--svg-path (excalidraw-file)
  "Return SVG path for EXCALIDRAW-FILE (same directory)."
  (replace-regexp-in-string "\\.excalidraw$" ".svg" excalidraw-file))

(defun org-excalidraw--export (input-file output-file &optional format)
  "Export INPUT-FILE to OUTPUT-FILE using kroki-cli.
FORMAT is 'svg', 'png', or 'pdf' (default: 'svg')."
  (let ((format (or format "svg")))
    (call-process org-excalidraw-converter-executable nil nil nil
                  "convert" input-file
                  "--type" "excalidraw"
                  "--format" format
                  "--out-file" output-file)))

(defun org-excalidraw--ensure-svg (excalidraw-file)
  "Ensure SVG exists and is up-to-date for EXCALIDRAW-FILE."
  (when excalidraw-file
    (let ((svg-path (org-excalidraw--svg-path excalidraw-file)))
      (if (file-exists-p excalidraw-file)
          (when (or (not (file-exists-p svg-path))
                    (file-newer-than-file-p excalidraw-file svg-path))
            (org-excalidraw--export excalidraw-file svg-path))
        (unless (file-exists-p svg-path)
          (message "Excalidraw file not found: %s" excalidraw-file)))
      (when (file-exists-p svg-path) svg-path))))

;;; Interactive Commands

(defun org-excalidraw-create (filename)
  "Create a new Excalidraw file and insert an org link.
FILENAME should start with 'excalidraw-' prefix."
  (interactive "sFilename (*.excalidraw): ")
  (unless (string-suffix-p ".excalidraw" filename)
    (setq filename (concat filename ".excalidraw")))
  (let ((full-path (expand-file-name filename default-directory)))
    (when (file-exists-p full-path)
      (user-error "File already exists: %s" full-path))
    (with-temp-file full-path
      (insert (json-encode (org-excalidraw--create-template))))
    (insert (format "[[excalidraw:%s]]" filename))
    (message "Created Excalidraw file: %s" filename)))

(defun org-excalidraw-link-open (link)
  "Open excalidraw LINK with resource opener according to the desktop environment."
  (let ((path (expand-file-name link)))
    (unless (string-suffix-p ".excalidraw" path)
      (error "Excalidraw diagrams must ends with .excalidraw extension."))
    (pcase system-type
      ('gnu/linux (shell-command (concat "xdg-open " (shell-quote-argument path))))
      ('darwin (shell-command (concat "open " (shell-quote-argument path))))
      (_ (message "Unsupported system type, only Linux/MacOS supported")))))

(defun org-excalidraw-refresh ()
  "Refresh the excalidraw image at point."
  (interactive)
  (let* ((link (org-element-property :path (org-element-context)))
         (full-path (expand-file-name link))
         (svg-path (org-excalidraw--svg-path full-path)))
    (when (and link (string-suffix-p ".excalidraw" link))
      (org-excalidraw--export full-path svg-path)
      (message "Refreshed: %s" link)
      (org-toggle-inline-images))))

(defun org-excalidraw-refresh-all ()
  "Refresh all excalidraw images in the current buffer."
  (interactive)
  (org-element-map (org-element-parse-buffer) 'link
    (lambda (link)
      (let* ((path (org-element-property :path link))
             (full-path (and path (expand-file-name path))))
        (when (and full-path (string-suffix-p ".excalidraw" full-path))
          (let ((svg-path (org-excalidraw--svg-path full-path)))
            (org-excalidraw--export full-path svg-path))))))
  (org-toggle-inline-images)
  (message "Refreshed all excalidraw images"))

;;; Org Integration

(defun org-excalidraw--get-size (&optional link)
  "Get width and height from #+ATTR_ORG: or defaults.
LINK is the org-element link object.  Return (WIDTH . HEIGHT)."
  (let* ((keyword (and link (org-element-lineage link '(keyword) t)))
         (value (when keyword (org-element-property :value keyword)))
         (width (and value
                     (string-match ":width\\s-+\\([0-9]+\\)" value)
                     (string-to-number (match-string 1 value))))
         (height (and value
                      (string-match ":height\\s-+\\([0-9]+\\)" value)
                      (string-to-number (match-string 1 value)))))
    (cons (or width org-excalidraw-default-width) height)))

(defun org-excalidraw-preview (ov path &optional link)
  "Display excalidraw PATH in overlay OV for LINK."
  (when (display-graphic-p)
    (let* ((full-path (expand-file-name path))
           (svg-path (org-excalidraw--ensure-svg full-path)))
      (when svg-path
        (let* ((size (org-excalidraw--get-size link))
               (image (create-image svg-path 'svg nil
                                    :width (car size)
                                    :height (cdr size))))
          (when image
            (image-flush image)
            (overlay-put ov 'display image)
            (overlay-put ov 'face 'default)
            (overlay-put ov 'keymap image-map)
            t))))))

(defun org-excalidraw-complete (&optional arg)
  "Complete excalidraw link with file name."
  (concat "excalidraw:" (read-file-name "Excalidraw file: " nil nil t nil
                                    (lambda (f) (string-suffix-p ".excalidraw" f)))))

(defun org-excalidraw-export-link (link desc format)
  "Export excalidraw LINK in FORMAT."
  (let* ((svg-path (and link (org-excalidraw--svg-path link))))
    (org-export-string-as (format "file:%s" svg-path) format t)))

(defun org-excalidraw-follow (path _)
  "Open excalidraw file at PATH."
  (org-excalidraw-link-open path))

;;; Initialization

(defun org-excalidraw-setup ()
  "Set up org-excalidraw."
  (require 'image)
  (org-link-set-parameters "excalidraw"
                           :follow #'org-excalidraw-follow
                           :export #'org-excalidraw-export-link
                           :preview #'org-excalidraw-preview
                           :complete #'org-excalidraw-complete))

(org-excalidraw-setup)

(provide 'org-excalidraw)
;;; org-excalidraw.el ends here
