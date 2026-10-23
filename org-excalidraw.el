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

;;; Placeholder logo

(defconst org-excalidraw--logo-svg
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"150\" height=\"150\" viewBox=\"0 0 150 150\">
  <rect width=\"150\" height=\"150\" rx=\"18\" fill=\"#f7f7f5\"/>
  <g transform=\"translate(75 75) rotate(40) translate(-75 -75)\">
    <rect x=\"68\" y=\"30\" width=\"14\" height=\"55\" rx=\"2\" fill=\"#1e1e1e\"/>
    <rect x=\"68\" y=\"24\" width=\"14\" height=\"8\" rx=\"3\" fill=\"#ffc83d\"/>
    <polygon points=\"68,85 82,85 75,103\" fill=\"#e0a96d\"/>
    <polygon points=\"75,103 72,96 78,96\" fill=\"#1e1e1e\"/>
  </g>
</svg>"
  "Inline SVG of the Excalidraw logo, shown as a placeholder while rendering.")

(defun org-excalidraw--logo-image ()
  "Return an image of the Excalidraw logo placeholder."
  (create-image org-excalidraw--logo-svg 'svg t
                :width 150 :height 150))

(defun org-excalidraw--show-image (ov svg-path width height)
  "Display the SVG at SVG-PATH in overlay OV at WIDTH/HEIGHT."
  (let ((image (create-image svg-path 'svg nil
                             :width width :height height)))
    (when image
      (image-flush image)
      (overlay-put ov 'display image)
      (overlay-put ov 'face 'default)
      (overlay-put ov 'keymap image-map))))

;;; Core Functions

(defun org-excalidraw--svg-path (excalidraw-file)
  "Return SVG path for EXCALIDRAW-FILE (same directory)."
  (replace-regexp-in-string "\\.excalidraw$" ".svg" excalidraw-file))

(defun org-excalidraw--export (input-file output-file &optional format)
  "Export INPUT-FILE to OUTPUT-FILE using kroki-cli.
FORMAT is `svg', `png', or `pdf' (default: `svg')."
  (let ((format (or format "svg")))
    (call-process org-excalidraw-converter-executable nil nil nil
                  "convert" input-file
                  "--type" "excalidraw"
                  "--format" format
                  "--out-file" output-file)))

(defun org-excalidraw--export-async (input-file output-file &optional format callback)
  "Asynchronously export INPUT-FILE to OUTPUT-FILE using kroki-cli.
FORMAT is `svg', `png', or `pdf' (default: `svg').
Call CALLBACK with t on success or nil on failure when finished."
  (let ((format (or format "svg")))
    (if (executable-find org-excalidraw-converter-executable)
        (let ((proc (start-process
                     "org-excalidraw-export" nil
                     org-excalidraw-converter-executable
                     "convert" input-file
                     "--type" "excalidraw"
                     "--format" format
                     "--out-file" output-file)))
          (set-process-sentinel
           proc
           (lambda (p _event)
             (funcall callback (and (eq (process-exit-status p) 0)
                                    (file-exists-p output-file))))))
      (message "Converter executable not found: %s"
               org-excalidraw-converter-executable)
      (funcall callback nil))))

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

(defun org-excalidraw--ensure-svg-async (excalidraw-file callback)
  "Asynchronously ensure the SVG for EXCALIDRAW-FILE is up-to-date.
Call CALLBACK with t when a usable SVG exists (already or after
generation) or nil otherwise."
  (if (not excalidraw-file)
      (funcall callback nil)
    (let ((svg-path (org-excalidraw--svg-path excalidraw-file)))
      (cond
       ((and (file-exists-p excalidraw-file)
             (file-exists-p svg-path)
             (not (file-newer-than-file-p excalidraw-file svg-path)))
        ;; Already up-to-date: no generation needed.
        (funcall callback t))
       ((file-exists-p excalidraw-file)
        (org-excalidraw--export-async excalidraw-file svg-path "svg" callback))
       (t
        (message "Excalidraw file not found: %s" excalidraw-file)
        (funcall callback nil))))))

;;; Interactive Commands

(defun org-excalidraw-create (filename)
  "Create a new Excalidraw file and insert an org link.
FILENAME should start with `excalidraw-' prefix."
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
  "Display excalidraw PATH in overlay OV for LINK.

Shows the Excalidraw logo immediately, then generates the SVG
asynchronously and swaps in the rendered image when it is ready, so
that displaying images never blocks the UI."
  (when (display-graphic-p)
    (let* ((full-path (expand-file-name path))
           (size (org-excalidraw--get-size link))
           (svg-path (org-excalidraw--svg-path full-path)))
      (cond
       ;; Cached SVG is up-to-date: display it directly, no waiting.
       ((and (file-exists-p full-path)
             (file-exists-p svg-path)
             (not (file-newer-than-file-p full-path svg-path)))
        (org-excalidraw--show-image ov svg-path (car size) (cdr size))
        t)
       ;; Needs (re)generation: show the logo first, render async, then load.
       ((file-exists-p full-path)
        (overlay-put ov 'display (org-excalidraw--logo-image))
        (overlay-put ov 'face 'default)
        (overlay-put ov 'keymap image-map)
        (org-excalidraw--ensure-svg-async
         full-path
         (lambda (ok)
           ;; Guard against the overlay having been removed meanwhile.
           (when (and ok (overlay-buffer ov) (file-exists-p svg-path))
             (org-excalidraw--show-image ov svg-path (car size) (cdr size)))))
        t)
       (t
        (message "Excalidraw file not found: %s" full-path)
        nil)))))

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

(provide 'org-excalidraw)
;;; org-excalidraw.el ends here
