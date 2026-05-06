#! @GUILE@ \
--no-auto-compile -e main -L @guile_site_dir@ -C @guile_site_ccache_dir@ -s
!#
;;; GNU Mes --- Maxwell Equations of Software
;;; Copyright © 2016,2017,2018,2019,2023 Jan (janneke) Nieuwenhuizen <janneke@gnu.org>
;;;
;;; This file is part of GNU Mes.
;;;
;;; GNU Mes is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Mes is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Mes.  If not, see <http://www.gnu.org/licenses/>.

(cond-expand
 (mes)
 (guile
  (define %arch (car (string-split %host-type #\-)))
  (define %kernel (car (filter
                        (compose not
                                 (lambda (x) (member x '("pc" "portbld" "unknown"))))
                        (cdr (string-split %host-type #\-)))))))

(define %prefix (or "/nix/store/vhbf57apsjqv01fnvhavm6iyk91m91si-mes-src-0.27.1/mes-0.27.1"
                      (if (string-prefix? "@prefix" "/nix/store/vhbf57apsjqv01fnvhavm6iyk91m91si-mes-src-0.27.1/mes-0.27.1")
                          ""
                          "/nix/store/vhbf57apsjqv01fnvhavm6iyk91m91si-mes-src-0.27.1/mes-0.27.1")))

(define %includedir (or "/nix/store/vhbf57apsjqv01fnvhavm6iyk91m91si-mes-src-0.27.1/mes-0.27.1/include"
                        (string-append %prefix "/include")))

(define %libdir (or "/nix/store/vhbf57apsjqv01fnvhavm6iyk91m91si-mes-src-0.27.1/mes-0.27.1/lib"
                    (string-append %prefix "/lib")))

(define %version (if (string-prefix? "@VERSION" "0.27.1") "git"
                     "0.27.1"))

(define %arch (if (string-prefix? "@mes_cpu" "x86_64") %arch
                  "x86_64"))

(define %kernel (if (string-prefix? "@mes_kernel" "linux") %kernel
                    "linux"))

(setenv "%prefix" %prefix)
(setenv "%includedir" %includedir)
(setenv "%libdir" %libdir)
(setenv "%version" %version)
(setenv "%arch" %arch)
(setenv "%kernel" %kernel)

(cond-expand
 (mes
  (if (current-module) (use-modules (mescc))
    (mes-use-module (mescc))))
 (guile
  (use-modules (mescc))))

(define (main args)
  (mescc:main args))
