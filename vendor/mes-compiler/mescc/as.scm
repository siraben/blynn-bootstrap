;;; GNU Mes --- Maxwell Equations of Software
;;; Copyright © 2016,2017,2018 Jan (janneke) Nieuwenhuizen <janneke@gnu.org>
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

(define-module (mescc as)
  #:use-module (srfi srfi-1)
  #:use-module (mes guile)
  #:use-module (mescc info)
  #:export (as
            dec->hex
            int->bv8
            int->bv16
            int->bv32
            int->bv64
            get-r
            get-r0
            get-r1
            get-r-1))

(define (int->bv64 value)
  (list (modulo value #x100)
        (modulo (ash value -8) #x100)
        (modulo (ash value -16) #x100)
        (modulo (ash value -24) #x100)
        (modulo (ash value -32) #x100)
        (modulo (ash value -40) #x100)
        (modulo (ash value -48) #x100)
        (modulo (ash value -56) #x100)))

(define (int->bv32 value)
  (list (modulo value #x100)
        (modulo (ash value -8) #x100)
        (modulo (ash value -16) #x100)
        (modulo (ash value -24) #x100)))

(define (int->bv16 value)
  (list (modulo value #x100)
        (modulo (ash value -8) #x100)))

(define (int->bv8 value)
  (list (modulo value #x100)))

(define (dec->hex o)
  (cond ((number? o) (number->string o 16))
        ((char? o) (number->string (char->integer o) 16))
        (else (format #f "~s" o))))

(define (as info instruction . rest)
  (if (pair? instruction)
      (append-map (lambda (o) (apply as (cons* info o rest))) instruction)
      (let ((proc (assoc-ref (.instructions info) instruction)))
        (if (not proc) (error "no such instruction" instruction)
            (apply proc info rest)))))

(define (get-r info)
  (car (if (pair? (.allocated info)) (.allocated info) (.registers info))))

(define (get-r0 info)
  (cadr (.allocated info)))

(define (get-r1 info)
  (car (.allocated info)))

(define (get-r-1 info)
  (caddr (.allocated info)))
