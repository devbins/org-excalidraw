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

(defcustom org-excalidraw-logo-file nil
  "Path to a custom Excalidraw logo SVG used as the loading placeholder.
When set, this file is used for every drawing.  When nil, an
`excalidraw-logo.svg' next to the source file is used if present,
otherwise the built-in placeholder is written there."
  :type '(choice (file :tag "Logo SVG file")
                 (const :tag "Per-directory / built-in" nil))
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
  "<svg xmlns='http://www.w3.org/2000/svg' width='1000' height='1000'>
  <rect width='1000' height='1000' rx='200' ry='200' fill='#fff' />
  <svg viewBox='0 0 107 101' xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' xml:space='preserve' style='fill-rule:evenodd;clip-rule:evenodd;stroke-linejoin:round;stroke-miterlimit:2'>
    <path style='fill:none' d='M24 17h121v121H24z' transform='matrix(.8843 0 0 .83471 -21.223 -14.19)' />
    <path d='M119.81 105.98a.549.549 0 0 0-.53-.12c-4.19-6.19-9.52-12.06-14.68-17.73l-.85-.93c0-.11-.05-.21-.12-.3a.548.548 0 0 0-.34-.2l-.17-.18-.12-.09c-.15-.32-.53-.56-.95-.35-1.58.81-3 1.97-4.4 3.04-1.87 1.43-3.7 2.92-5.42 4.52-.7.65-1.39 1.33-1.97 2.09-.28.37-.07.72.27.87-1.22 1.2-2.45 2.45-3.68 3.74-.11.12-.17.28-.16.44.01.16.09.31.22.41l2.16 1.65s.01.03.03.04c3.09 3.05 8.51 7.28 14.25 11.76.85.67 1.71 1.34 2.57 2.01.39.47.76.94 1.12 1.4.19.25.55.3.8.11.13.1.26.21.39.31a.57.57 0 0 0 .8-.1c.07-.09.1-.2.11-.31.04 0 .07.03.1.03.15 0 .31-.06.42-.18l10.18-11.12a.56.56 0 0 0-.04-.8l.01-.01Zm-29.23-3.85c.07.09.14.17.21.25 1.16.98 2.4 2.04 3.66 3.12l-5.12-3.91s-.32-.22-.52-.36c-.11-.08-.21-.16-.31-.24l-.38-.32s.07-.07.1-.11l.35-.35c1.72-1.74 4.67-4.64 6.19-6.06-1.61 1.62-4.87 6.37-4.17 7.98h-.01Zm17.53 13.81-4.22-3.22c-1.65-1.71-3.43-3.4-5.24-5.03 2.28 1.76 4.23 3.25 4.52 3.51 2.21 1.97 2.11 1.61 3.63 2.91l1.83 1.33c-.18.16-.36.33-.53.49l.01.01Zm1.06.81-.08-.06c.16-.13.33-.25.49-.38l-.4.44h-.01ZM42.24 51.45c.14.72.27 1.43.4 2.11.69 3.7 1.33 7.03 2.55 9.56l.48 1.92c.19.73.46 1.64.71 1.83 2.85 2.52 7.22 6.28 11.89 9.82.21.16.5.15.7-.01.01.02.03.03.04.04.11.1.24.15.38.15.16 0 .31-.06.42-.19 5.98-6.65 10.43-12.12 13.6-16.7.2-.25.3-.54.29-.84.2-.24.41-.48.6-.68a.558.558 0 0 0-.1-.86.578.578 0 0 0-.17-.36c-1.39-1.34-2.42-2.31-3.46-3.28-1.84-1.72-3.74-3.5-7.77-7.51-.02-.02-.05-.04-.07-.06a.555.555 0 0 0-.22-.14c-1.11-.39-3.39-.78-6.26-1.28-4.22-.72-10-1.72-15.2-3.27h-.04v-.01s-.02 0-.03.02h-.01l.04-.02s-.31.01-.37.04c-.08.04-.14.09-.19.15-.05.06-.09.12-.47.2-.38.08.08 0 .11 0h-.11v.03c.07.34.05.58.16.97-.02.1.21 1.02.24 1.11l1.83 7.26h.03Zm30.95 6.54s-.03.04-.04.05l-.64-.71c.22.21.44.42.68.66Zm-7.09 9.39s-.07.08-.1.12l-.02-.02c.04-.03.08-.07.13-.1h-.01Zm-7.07 8.47Zm3.02-28.57c.35.35 1.74 1.65 2.06 1.97-1.45-.66-5.06-2.34-6.74-2.88 1.65.29 3.93.66 4.68.91Zm-19.18-2.77c.84 1.44 1.5 6.49 2.16 11.4-.37-1.58-.69-3.12-.99-4.6-.52-2.56-1-4.85-1.67-6.88.14.01.31.03.49.05 0 .01 0 .02.02.03h-.01Zm-.29-1.21c-.23-.02-.44-.04-.62-.05-.02-.04-.03-.08-.04-.12l.66.18v-.01Zm-2.22.45v-.02.02ZM118.9 42.57c.04-.23-1.1-1.24-.74-1.26.85-.04.86-1.35 0-1.31-1.13.06-2.27.32-3.37.53-1.98.37-3.95.78-5.92 1.21-4.39.94-8.77 1.93-13.1 3.11-1.36.37-2.86.7-4.11 1.36-.42.22-.4.67-.17.95-.09.05-.18.08-.28.09-.37.07-.74.13-1.11.19a.566.566 0 0 0-.39.86c-2.32 3.1-4.96 6.44-7.82 9.95-2.81 3.21-5.73 6.63-8.72 10.14-9.41 11.06-20.08 23.6-31.9 34.64-.23.21-.24.57-.03.8.05.06.12.1.19.13-.16.15-.32.3-.48.44-.1.09-.14.2-.16.32-.08.08-.16.17-.23.25-.21.23-.2.59.03.8.23.21.59.2.8-.03.04-.04.08-.09.12-.13a.84.84 0 0 1 1.22 0c.69.74 1.34 1.44 1.95 2.09l-1.38-1.15a.57.57 0 0 0-.8.07c-.2.24-.17.6.07.8l14.82 12.43c.11.09.24.13.37.13.15 0 .29-.06.4-.17l.36-.36a.56.56 0 0 0 .63-.12c20.09-20.18 36.27-35.43 54.8-49.06.17-.12.25-.32.23-.51a.57.57 0 0 0 .48-.39c3.42-10.46 4.08-19.72 4.28-24.27 0-.03.01-.05.02-.07.02-.05.03-.1.04-.14.03-.11.05-.19.05-.19.26-.78.17-1.53-.15-2.15v.02ZM82.98 58.94c.9-1.03 1.79-2.04 2.67-3.02-5.76 7.58-15.3 19.26-28.81 33.14 9.2-10.18 18.47-20.73 26.14-30.12Zm-32.55 52.81-.03-.03c.11.02.19.04.2.04a.47.47 0 0 0-.17 0v-.01Zm6.9 6.42-.05-.04.03-.03c.02 0 .03.02.04.02 0 .02-.02.03-.03.05h.01Zm8.36-7.21 1.38-1.44c.01.01.02.03.03.05-.47.46-.94.93-1.42 1.39h.01Zm2.24-2.21c.26-.3.56-.65.87-1.02.01-.01.02-.03.04-.04 3.29-3.39 6.68-6.82 10.18-10.25.02-.02.05-.04.07-.06.86-.66 1.82-1.39 2.72-2.08-4.52 4.32-9.11 8.78-13.88 13.46v-.01Zm21.65-55.88c-1.86 2.42-3.9 5.56-5.63 8.07-5.46 7.91-23.04 27.28-23.43 27.65-2.71 2.62-10.88 10.46-16.09 15.37-.14.13-.25.24-.34.35a.794.794 0 0 1 .03-1.13c24.82-23.4 39.88-42.89 46-51.38-.13.33-.24.69-.55 1.09l.01-.02Zm16.51 7.1-.01.02c0-.02-.02-.07.01-.02Zm-.91-5.13Zm-5.89 9.45c-2.26-1.31-3.32-3.27-2.71-5.25l.19-.66c.08-.19.17-.38.28-.57.59-.98 1.49-1.85 2.52-2.36.05-.02.1-.03.15-.04a.795.795 0 0 1-.04-.43c.05-.31.25-.58.66-.58.67 0 2.75.62 3.54 1.3.24.19.47.4.68.63.3.35.74.92.96 1.33.13.06.23.62.38.91.14.46.2.93.18 1.4 0 .02 0 .02.01.03-.03.07 0 .37-.04.4-.1.72-.36 1.43-.75 2.05-.04.05-.07.11-.11.16 0 .01-.02.02-.03.04-.3.43-.65.83-1.08 1.13-1.26.89-2.73 1.16-4.2.79a6.33 6.33 0 0 1-.57-.25l-.02-.03Zm16.27-1.63c-.49 2.05-1.09 4.19-1.8 6.38-.03.08-.03.16-.03.23-.1.01-.19.05-.27.11-4.44 3.26-8.73 6.62-12.98 10.11 3.67-3.32 7.39-6.62 11.23-9.95a6.409 6.409 0 0 0 2.11-3.74l.56-3.37.03-.1c.25-.71 1.34-.4 1.17.33h-.02Z' style='fill:#6965db;fill-rule:nonzero' transform='matrix(1 0 0 1 -26.41 -29.49)' />
  </svg>
</svg>"
  "Built-in official Excalidraw logo, embedded inline (no external file).
Rendered directly from this string via `create-image' (no temp file).")

(defun org-excalidraw--logo-image (&optional _excalidraw-file)
  "Return an image of the Excalidraw logo placeholder.
Uses `org-excalidraw-logo-file' if set (file-based), otherwise the
inline logo rendered directly from its SVG string (no temp file)."
  (if (and org-excalidraw-logo-file (file-exists-p org-excalidraw-logo-file))
      (create-image org-excalidraw-logo-file 'svg nil :width 300)
    (create-image org-excalidraw--logo-svg 'svg t :width 300)))

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
        (overlay-put ov 'display (org-excalidraw--logo-image full-path))
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
