;;; GNU Mes --- Maxwell Equations of Software
;;; Copyright © 2018 Jan (janneke) Nieuwenhuizen <janneke@gnu.org>
;;; Copyright © 2021 W. J. van der Laan <laanwj@protonmail.com>
;;; Copyright © 2023 Andrius Štikonas <andrius@stikonas.eu>
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

;;; Commentary:

;;; Define riscv64 M1 assembly

;;; Code:

(define-module (mescc riscv64 as)
  #:use-module (mes guile)
  #:use-module (mescc as)
  #:use-module (mescc info)
  #:use-module (mescc riscv64 info)
  #:export (
            riscv64:instructions
            ))

;;; reserved temporary intermediate registers
;;; t6 is used internally by M1 sequences
;;; t4 and t5 are scratch registers for code generation here
(define %tmpreg1 "t5")
(define %tmpreg2 "t4")
;;; registers for condition flags emulation
(define %condregx "s10")
(define %condregy "s11")

;;; register for return values
(define %retreg "t0")
(define %zero "x0")

;;; internal: return instruction to load an intermediate value into a register
(define (riscv64:li r v)
  (riscv64:addi r %zero v))

;;; internal: return instruction to add an intermediate value into a register
(define (riscv64:addi r0 r1 v)
  (cond
   ((= v 0)
    `(,(string-append "rd_" r0 " rs1_" r1 " addi"))) ; nothing to do
   ((and (>= v (- #x800)) (<= v #x7ff))
    `(,(string-append "rd_" r0 " rs1_" r1 " !" (number->string v) " addi")))
   ((and (>= v (- #x80000000)) (<= v #x7fffffff))
    `(,(string-append "rd_t6 auipc\n\t"
                      "rd_t6 rs1_t6 !16 lw\n\t"
                      "rd_" r0 " rs1_" r1 " rs2_t6 add\n\t"
                      "!8 jal\n\t") (#:immediate ,v)))
   (else
    `(,(string-append "rd_" r0 " auipc\n\t"
                      "rd_" r0 " rs1_" r0 " !16 ld\n\t"
                      "rd_" r0 " rs1_" r0 " rs2_" r1 " add\n\t"
                      "!12 jal\n\t") (#:immediate8 ,v)))))

;;; internal: return instruction to save address of the label into register
(define (riscv64:label_address r label)
  `((,(string-append "rd_" r) (#:u-format ,label) "auipc\n\t")
    ,(string-append "rd_" r " rs1_" r) (#:i-format ,label) "addiw"))

(define (riscv64:push r)
  (string-append "rd_sp rs1_sp !-8 addi
	rs1_sp rs2_" r " sd"))

(define (riscv64:pop r)
  (string-append "rd_" r " rs1_sp ld
	rd_sp rs1_sp !8 addi"))

;;; the preamble of every function
(define (riscv64:function-preamble info . rest)
  `(("rd_sp rs1_sp !-8 addi
	rs1_sp rs2_ra sd") ; push ra to stack
    ("rd_sp rs1_sp !-8 addi
	rs1_sp rs2_fp sd") ; push fp to stack
    ("rd_fp rs1_sp mv")))

;;; allocate function locals
(define (riscv64:function-locals . rest)
  `(
    ,(riscv64:addi "sp" "sp" (- (+ (* 8 1025) (* 20 8))))
    )) ; 8*1024 buf, 20 local vars

;;; immediate value to register
(define (riscv64:value->r info v)
  (or v (error "invalid value: riscv64:value->r: " v))
  (let ((r (get-r info)))
    `(,(riscv64:li r v))))

;;; assign immediate value to r0
(define (riscv64:value->r0 info v)
  (let ((r0 (get-r0 info)))
    `(,(riscv64:li r0 v))))

;;; function epilogue
(define (riscv64:ret . rest)
  `(("rd_sp rs1_fp mv")
    (,(riscv64:pop "fp"))
    (,(riscv64:pop "ra"))
    ("ret")))

;;; stack local to register
(define (riscv64:local->r info n)
  (let ((r (car (if (pair? (.allocated info)) (.allocated info) (.registers info))))
        (n (- 0 (* 8 n))))
    `(,(riscv64:addi %tmpreg1 "fp" n)
      (,(string-append "rd_" r " rs1_" %tmpreg1 " ld")))))

;;; call a function through a label
(define (riscv64:call-label info label n)
  `(("rd_ra" (#:j-format ,label) "jal")
    ,(riscv64:addi "sp" "sp" (* n 8))))

;;; call function pointer in register
(define (riscv64:call-r info n)
  (let ((r (get-r info)))
    `((,(string-append "rd_ra rs1_" r " jalr"))
      ,(riscv64:addi "sp" "sp" (* n 8)))))

;;; register to function argument.
(define (riscv64:r->arg info i)
  (let ((r (get-r info)))
    `((,(riscv64:push r)))))

;;; label to function argument
(define (riscv64:label->arg info label i)
  `(,(riscv64:label_address %tmpreg1 label)
    (,(riscv64:push %tmpreg1))))

;;; ALU: r0 := r0 + r1
(define (riscv64:r0+r1 info)
  (let ((r1 (get-r1 info))
        (r0 (get-r0 info)))
    `((,(string-append "rd_" r0 " rs1_" r0 " rs2_" r1 " add")))))

;;; ALU: r0 := r0 - r1
(define (riscv64:r0-r1 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" r0 " rs1_" r0 " rs2_" r1 " sub")))))

;;; add immediate value to r0
(define (riscv64:r0+value info v)
  (let ((r0 (get-r0 info)))
    `(,(riscv64:addi r0 r0 v))))

;;; add immediate to contents of 8-bit word addressed by register
(define (riscv64:r-byte-mem-add info v)
  (let ((r (get-r info)))
    `((,(string-append "rd_" %tmpreg1 " rs1_" r " lb"))
      ,(riscv64:addi %tmpreg1 %tmpreg1 v)
      (,(string-append "rs1_" r " rs2_" %tmpreg1 " sb")))))

;;; add immediate to contents of 16-bit word addressed by register
(define (riscv64:r-word-mem-add info v)
  (let ((r (get-r info)))
    `((,(string-append "rd_" %tmpreg1 " rs1_" r " lh"))
      ,(riscv64:addi %tmpreg1 %tmpreg1 v)
      (,(string-append "rs1_" r " rs2_" %tmpreg1 " sh")))))

;;; add immediate to contents of 32-bit word addressed by register
(define (riscv64:r-long-mem-add info v)
  (let ((r (get-r info)))
    `((,(string-append "rd_" %tmpreg1 " rs1_" r " lw"))
      ,(riscv64:addi %tmpreg1 %tmpreg1 v)
      (,(string-append "rs1_" r " rs2_" %tmpreg1 " sw")))))

;;; add immediate to contents of 64-bit word addressed by register
(define (riscv64:r-mem-add info v)
  (let ((r (get-r info)))
    `((,(string-append "rd_" %tmpreg1 " rs1_" r " ld"))
      ,(riscv64:addi %tmpreg1 %tmpreg1 v)
      (,(string-append "rs1_" r " rs2_" %tmpreg1 " sd")))))

;;; compute address of local variable and write result into register
(define (riscv64:local-ptr->r info n)
  (let ((r (get-r info))
        (n (- 0 (* 8 n))))
    `((,(string-append "rd_" r " rs1_fp mv"))
      ,(riscv64:addi r r n))))

;;; label address into register
(define (riscv64:label->r info label)
  (let ((r (get-r info)))
    `(,(riscv64:label_address r label))))

;;; copy register r0 to register r1 (see also r1->r0)
(define (riscv64:r0->r1 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append  "rd_" r1 " rs1_" r0 " mv")))))

;;; copy register r1 to register r0 (see also r0->r1)
(define (riscv64:r1->r0 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append  "rd_" r0 " rs1_" r1 " mv")))))

;;; zero-extend 8-bit in register r
(define (riscv64:byte-r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" r " !0xFF andi")))))

;;; sign-extend 8-bit in register r
(define (riscv64:byte-signed-r info)
  (let ((r (get-r info)))
    `((,(riscv64:li %tmpreg1 56)
       ,(string-append "\n\trd_" r " rs1_" r " rs2_" %tmpreg1 " sll\n\t")
       ,(string-append "rd_" r " rs1_" r " rs2_" %tmpreg1 " sra")))))

;;; zero-extend 16-bit in register r
(define (riscv64:word-r info)
  (let ((r (get-r info)))
    `((,(riscv64:li %tmpreg1 #xffff)
       ,(string-append "rd_" r " rs1_" r " rs2_" %tmpreg1 " and")))))

;;; sign-extend 16-bit in register r
(define (riscv64:word-signed-r info)
  (let ((r (get-r info)))
    `((,(riscv64:li %tmpreg1 48)
       ,(string-append "\n\trd_" r " rs1_" r " rs2_" %tmpreg1 " sll\n\t")
       ,(string-append "rd_" r " rs1_" r " rs2_" %tmpreg1 " sra")))))

;;; zero-extend 32-bit in register r
(define (riscv64:long-r info)
  (let ((r (get-r info)))
    `((,(riscv64:li %tmpreg1 #xffffffff)
       ,(string-append "rd_" r " rs1_" r " rs2_" %tmpreg1 " and")))))

;;; sign-extend 32-bit in register r
(define (riscv64:long-signed-r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" r " addiw")))))

;;; unconditional jump to label
(define (riscv64:jump info label)
  `(((#:j-format ,label) "jal")))

;;;; Flag setters ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; test if a register is zero, set z flag accordingly
;;; see also test-r
(define (riscv64:r-zero? info)
  (let ((r (car (if (pair? (.allocated info)) (.allocated info) (.registers info)))))
    `((,(string-append "rd_" %condregx " rs1_" r " mv"))
      ,(riscv64:li %condregy 0))))

;;; test register r against 0 and set flags
;;; this is used for jump-* and cc?->r:
;;; z (both)
;;; g ge l le (signed)
;;; a ae b be (unsigned)
(define (riscv64:test-r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" %condregx " rs1_" r " mv"))
      ,(riscv64:li %condregy 0))))

;;; negate zero flag
(define (riscv64:xor-zf info)
  `((,(string-append "rd_" %condregx " rs1_" %condregx " rs2_" %condregy " sub\n\t"
                     "rd_" %condregx " rs1_" %condregx) (#:i-format 1) "sltiu\n\t"
                     ,(string-append "rd_" %condregy " addi"))))

;;; compare register to immediate value and set flags (see test-r)
(define (riscv64:r-cmp-value info v)
  (let ((r (get-r info)))
    `((,(string-append "rd_" %condregx " rs1_" r " mv"))
      ,(riscv64:li %condregy v))))

;;; compare register to another register and set flags (see test-r)
(define (riscv64:r0-cmp-r1 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" %condregx " rs1_" r0 " mv"))
      (,(string-append "rd_" %condregy " rs1_" r1 " mv")))))

;;;; Flag users ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; flag-based conditional jumps (equality)
(define (riscv64:jump-nz info label)
  `((,(string-append "rs1_" %condregx " rs2_" %condregy " @8 beq\n\t")
     (#:j-format ,label) "jal")))

(define (riscv64:jump-z info label)
  `((,(string-append "rs1_" %condregx " rs2_" %condregy " @8 bne\n\t")
     (#:j-format ,label) "jal")))

                                        ; assuming the result was properly zero/sign-extended, this is the same as a
                                        ; normal jump-z
(define (riscv64:jump-byte-z info label)
  `((,(string-append "rs1_" %condregx " rs2_" %condregy " @8 bne\n\t")
     (#:j-format ,label) "jal")))

;;; zero flag to register
(define (riscv64:zf->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" %condregx " rs2_" %condregy " sub\n\t"
                       "rd_" r " rs1_" r) (#:i-format 1) "sltiu"))))

;;; boolean: r := !e
(define (riscv64:r-negate info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" %condregx " rs2_" %condregy " sub\n\t"
                       "rd_" r " rs1_" r) (#:i-format 1) "sltiu"))))

;; flag-based conditional setters (signed)
(define (riscv64:g?->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" %condregy " rs2_" %condregx " slt")))))

(define (riscv64:ge?->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" %condregx " rs2_" %condregy " slt\n\t"
                       "rd_" r " rs1_" r) (#:i-format 1) "sltiu"))))

(define (riscv64:l?->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" %condregx " rs2_" %condregy " slt")))))

(define (riscv64:le?->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" %condregy " rs2_" %condregx " slt\n\t"
                       "rd_" r " rs1_" r) (#:i-format 1) "sltiu"))))

;; flag-based conditional setters (unsigned)
(define (riscv64:a?->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" %condregy  " rs2_" %condregx " sltu")))))

(define (riscv64:ae?->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" %condregx " rs2_" %condregy " sltu\n\t"
                       "rd_" r " rs1_" r) (#:i-format 1) "sltiu"))))

(define (riscv64:b?->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" %condregx  " rs2_" %condregy " sltu")))))

(define (riscv64:be?->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" %condregy " rs2_" %condregx " sltu\n\t"
                       "rd_" r " rs1_" r) (#:i-format 1) "sltiu"))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; store lower 8-bit of r0 at address r1
(define (riscv64:byte-r0->r1-mem info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rs1_" r1 " rs2_" r0 " sb")))))

;;; load word at label into register r
(define (riscv64:label-mem->r info label)
  (let ((r (get-r info)))
    `(,(riscv64:label_address %tmpreg1 label)
      (,(string-append "rd_" r " rs1_" %tmpreg1 " ld")))))

;;; read 8-bit (and zero-extend) from address in register r into register r
(define (riscv64:byte-mem->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" r " lbu")))))

;;; read 16-bit (and zero-extend) from address in register r into register r
(define (riscv64:word-mem->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" r " lhu")))))

;;; read 32-bit (and zero-extend) from address in register r into register r
(define (riscv64:long-mem->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" r " lwu")))))

;;; read 64-bit from address in register r into register r
(define (riscv64:mem->r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" r " ld")))))

(define (riscv64:local-add info n v)
  (let ((n (- 0 (* 8 n))))
    `(,(riscv64:li %tmpreg1 n)
      (,(string-append "rd_" %tmpreg1 " rs1_" %tmpreg1 " rs2_fp add"))
      (,(string-append "rd_" %tmpreg2 " rs1_" %tmpreg1 " ld"))
      ,(riscv64:addi %tmpreg2 %tmpreg2 v)
      (,(string-append "rs1_" %tmpreg1 " rs2_" %tmpreg2 " sd")))))

(define (riscv64:label-mem-add info label v)
  `(,(riscv64:label_address %tmpreg1 label)
    (,(string-append "rd_" %tmpreg2 " rs1_" %tmpreg1 " ld"))
    ,(riscv64:addi %tmpreg2 %tmpreg2 v)
    (,(string-append "rs1_" %tmpreg1 " rs2_" %tmpreg2 " sd"))))

;; no-operation
(define (riscv64:nop info)
  '(("nop")))

;; swap the contents of register r0 and r1
(define (riscv64:swap-r0-r1 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" %tmpreg1 " rs1_" r1 " mv"))
      (,(string-append "rd_" r1 " rs1_" r0 " mv"))
      (,(string-append "rd_" r0 " rs1_" %tmpreg1 " mv")))))

;;; write 8-bit from register r to memory at the label
(define (riscv64:r->byte-label info label)
  (let ((r (get-r info)))
    `(,(riscv64:label_address %tmpreg1 label)
      (,(string-append "rs1_" %tmpreg1 " rs2_" r " sb")))))

;;; write 16-bit from register r to memory at the label
(define (riscv64:r->word-label info label)
  (let ((r (get-r info)))
    `(,(riscv64:label_address %tmpreg1 label)
      (,(string-append "rs1_" %tmpreg1 " rs2_" r " sh")))))

;;; write 32-bit from register r to memory at the label
(define (riscv64:r->long-label info label)
  (let ((r (get-r info)))
    `(,(riscv64:label_address %tmpreg1 label)
      (,(string-append "rs1_" %tmpreg1 " rs2_" r " sw")))))

;;; write 64-bit from register r to memory at the label
(define (riscv64:r->label info label)
  (let ((r (get-r info)))
    `(,(riscv64:label_address %tmpreg1 label)
      (,(string-append "rs1_" %tmpreg1 " rs2_" r " sd")))))

;;; ALU r0 := r0 * r1
(define (riscv64:r0*r1 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" r0 " rs1_" r0 " rs2_" r1 " mul")))))

;;; bitwise r0 := r0 << r1
(define (riscv64:r0<<r1 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" r0 " rs1_" r0 " rs2_" r1 " sll")))))

;;; bitwise r0 := r0 << imm
(define (riscv64:shl-r info n)
  (let ((r (get-r info)))
    `(,(riscv64:li %tmpreg1 n)
      (,(string-append "rd_" r " rs1_" r " rs2_" %tmpreg1 " sll")))))

;;; bitwise r0 := r0 >> r1 (logical, so shift in zero bits)
(define (riscv64:r0>>r1 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" r0 " rs1_" r0 " rs2_" r1 " srl")))))

(define (riscv64:r0>>r1-signed info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" r0 " rs1_" r0 " rs2_" r1 " sra")))))

;;; bitwise r0 := r0 & r1
(define (riscv64:r0-and-r1 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" r0 " rs1_" r0 " rs2_" r1 " and")))))

;;; bitwise r0 := r0 | r1
(define (riscv64:r0-or-r1 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" r0 " rs1_" r0 " rs2_" r1 " or")))))

;;; bitwise r := r & imm
(define (riscv64:r-and info n)
  (let ((r (get-r info)))
    `(,(riscv64:li %tmpreg1 n)
      (,(string-append "rd_" r " rs1_" r " rs2_" %tmpreg1 " and")))))

;;; bitwise r0 := r0 ^ r1
(define (riscv64:r0-xor-r1 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" r0 " rs1_" r0 " rs2_" r1 " xor")))))

;;; ALU r0 := r0 / r1
(define (riscv64:r0/r1 info signed?)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" r0 " rs1_" r0 " rs2_" r1 " div")))))

;;; ALU r0 := r0 % r1
(define (riscv64:r0%r1 info signed?)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rd_" r0 " rs1_" r0 " rs2_" r1 " rem")))))

;;; ALU r0 := r0 + imm
(define (riscv64:r+value info v)
  (let ((r (get-r info)))
    `(,(riscv64:addi r r v))))

;;; store 8-bit r0 into address ported by r1
(define (riscv64:byte-r0->r1-mem info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rs1_" r1 " rs2_" r0 " sb")))))

;;; store 16-bit r0 into address ported by r1
(define (riscv64:word-r0->r1-mem info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rs1_" r1 " rs2_" r0 " sh")))))

;;; store 32-bit r0 into address ported by r1
(define (riscv64:long-r0->r1-mem info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rs1_" r1 " rs2_" r0 " sw")))))

;;; store 64-bit r0 into address ported by r1
(define (riscv64:r0->r1-mem info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info)))
    `((,(string-append "rs1_" r1 " rs2_" r0 " sd")))))

;;; push register to stack
(define (riscv64:push-register info r)
  `((,(riscv64:push r))))

;;; push register r0 to stack (see also push-register)
(define (riscv64:push-r0 info)
  (let ((r0 (get-r0 info)))
    `((,(riscv64:push r0)))))

;;; pop register from stack
(define (riscv64:pop-register info r)
  `((,(riscv64:pop r))))

;;; pop register r0 from stack (see also pop-register)
(define (riscv64:pop-r0 info)
  (let ((r0 (get-r0 info)))
    `((,(riscv64:pop r0)))))

;;; get function return value
(define (riscv64:return->r info)
  (let ((r (car (.allocated info))))
    (if (equal? r %retreg) '()
        `((,(string-append "rd_" r " rs1_" %retreg " mv"))))))

;;; bitwise r := r + r (doubling)
(define (riscv64:r+r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" r " rs2_" r " add")))))

;;; bitwise r := ~r
(define (riscv64:not-r info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" r " rs1_" r " not")))))

;;; load 8-bit at address r0, store to address r1
(define (riscv64:byte-r0-mem->r1-mem info)
  (let* ((r0 (get-r0 info))
         (r1 (get-r1 info)))
    `((,(string-append "rd_" %tmpreg1 " rs1_" r0 " lb"))
      (,(string-append "rs1_" r1 " rs2_" %tmpreg1 " sb")))))

;;; load 16-bit at address r0, store to address r1
(define (riscv64:word-r0-mem->r1-mem info)
  (let* ((r0 (get-r0 info))
         (r1 (get-r1 info)))
    `((,(string-append "rd_" %tmpreg1 " rs1_" r0 " lh"))
      (,(string-append "rs1_" r1 " rs2_" %tmpreg1 " sh")))))

;;; load 32-bit at address r0, store to address r1
(define (riscv64:long-r0-mem->r1-mem info)
  (let* ((r0 (get-r0 info))
         (r1 (get-r1 info)))
    `((,(string-append "rd_" %tmpreg1 " rs1_" r0 " lw"))
      (,(string-append "rs1_" r1 " rs2_" %tmpreg1 " sw")))))

;;; load 64-bit at address r0, store to address r1
(define (riscv64:r0-mem->r1-mem info)
  (let* ((r0 (get-r0 info))
         (r1 (get-r1 info)))
    `((,(string-append "rd_" %tmpreg1 " rs1_" r0 " ld"))
      (,(string-append "rs1_" r1 " rs2_" %tmpreg1 " sd")))))

;;; register (8-bit) to stack local
(define (riscv64:byte-r->local+n info id n)
  (let ((n (+ (- 0 (* 8 id)) n))
        (r (get-r info)))
    `(,(riscv64:addi %tmpreg1 "fp" n)
      (,(string-append "rs1_" %tmpreg1 " rs2_" r " sb")))))

;;; register (16-bit) to stack local
(define (riscv64:word-r->local+n info id n)
  (let ((n (+ (- 0 (* 8 id)) n))
        (r (get-r info)))
    `(,(riscv64:addi %tmpreg1 "fp" n)
      (,(string-append "rs1_" %tmpreg1 " rs2_" r " sh")))))

;;; register (32-bit) to stack local
(define (riscv64:long-r->local+n info id n)
  (let ((n (+ (- 0 (* 8 id)) n))
        (r (get-r info)))
    `(,(riscv64:addi %tmpreg1 "fp" n)
      (,(string-append "rs1_" %tmpreg1 " rs2_" r " sw")))))

;;; register (64-bit) to stack local
(define (riscv64:r->local info n)
  (let ((r (get-r info))
        (n (- 0 (* 8 n))))
    `(,(riscv64:addi %tmpreg1 "fp" n)
      (,(string-append "rs1_" %tmpreg1 " rs2_" r " sd")))))

;;; register (64-bit) to stack local (how does this differ from r->local ?)
;;; n is computed differently
(define (riscv64:r->local+n info id n)
  (let ((n (+ (- 0 (* 8 id)) n))
        (r (get-r info)))
    `(,(riscv64:addi %tmpreg1 "fp" n)
      (,(string-append "rs1_" %tmpreg1 " rs2_" r " sd")))))

;;; swap value of register r with the top word of the stack
;; seems unused
(define (riscv64:swap-r-stack info)
  (let ((r (get-r info)))
    `((,(string-append "rd_" %tmpreg1 " rs1_sp ld"))
      (,(string-append "rs1_sp rs2_" r " sd"))
      (,(string-append "rd_" r " rs1_" %tmpreg1 " mv")))))

;;; swap value of register r0 (not r1) with the top word of the stack
;; used in expr->arg
(define (riscv64:swap-r1-stack info)
  (let ((r0 (get-r0 info)))
    `((,(string-append "rd_" %tmpreg1 " rs1_sp ld"))
      (,(string-append "rs1_sp rs2_" r0 " sd"))
      (,(string-append "rd_" r0 " rs1_" %tmpreg1 " mv")))))

;;; not entirely sure what this is supposed to do
;;; i guess the idea would be to copy register r2 to r1, but what is the pop/push about?
(define (riscv64:r2->r0 info)
  (let ((r0 (get-r0 info))
        (r1 (get-r1 info))
        (allocated (.allocated info)))
    (if (> (length allocated) 2)
        (let ((r2 (cadddr allocated)))
          `((,(string-append  "rd_" r1 " rs1_" r2 " mv"))))
        `((,(riscv64:pop r0))
          (,(riscv64:push r0))))))

(define riscv64:instructions
  `(
    (a?->r . ,riscv64:a?->r)
    (ae?->r . ,riscv64:ae?->r)
    (b?->r . ,riscv64:b?->r)
    (be?->r . ,riscv64:be?->r)
    (byte-mem->r . ,riscv64:byte-mem->r)
    (byte-r . ,riscv64:byte-r)
    (byte-r->local+n . ,riscv64:byte-r->local+n)
    (byte-r0->r1-mem . ,riscv64:byte-r0->r1-mem)
    (byte-r0-mem->r1-mem . ,riscv64:byte-r0-mem->r1-mem)
    (byte-signed-r . ,riscv64:byte-signed-r)
    (call-label . ,riscv64:call-label)
    (call-r . ,riscv64:call-r)
    (function-locals . ,riscv64:function-locals)
    (function-preamble . ,riscv64:function-preamble)
    (g?->r . ,riscv64:g?->r)
    (ge?->r . ,riscv64:ge?->r)
    (jump . ,riscv64:jump)
    ;; (jump-a . ,riscv64:jump-a)
    ;; (jump-ae . ,riscv64:jump-ae)
    ;; (jump-b . ,riscv64:jump-b)
    ;; (jump-be . ,riscv64:jump-be)
    (jump-byte-z . ,riscv64:jump-byte-z)
    ;; (jump-g . , riscv64:jump-g)
    ;; (jump-ge . , riscv64:jump-ge)
    ;; (jump-l . ,riscv64:jump-l)
    ;; (jump-le . ,riscv64:jump-le)
    (jump-nz . ,riscv64:jump-nz)
    (jump-z . ,riscv64:jump-z)
    (l?->r . ,riscv64:l?->r)
    (label->arg . ,riscv64:label->arg)
    (label->r . ,riscv64:label->r)
    (label-mem->r . ,riscv64:label-mem->r)
    (label-mem-add . ,riscv64:label-mem-add)
    (le?->r . ,riscv64:le?->r)
    (local->r . ,riscv64:local->r)
    (local-add . ,riscv64:local-add)
    (local-ptr->r . ,riscv64:local-ptr->r)
    (long-mem->r . ,riscv64:long-mem->r)
    (long-r . ,riscv64:long-r)
    (long-r->local+n . ,riscv64:long-r->local+n)
    (long-r0->r1-mem . ,riscv64:long-r0->r1-mem)
    (long-r0-mem->r1-mem . ,riscv64:long-r0-mem->r1-mem)
    (long-signed-r . ,riscv64:long-signed-r)
    (mem->r . ,riscv64:mem->r)
    (nop . ,riscv64:nop)
    (not-r . ,riscv64:not-r)
    (pop-r0 . ,riscv64:pop-r0)
    (pop-register . ,riscv64:pop-register)
    (push-r0 . ,riscv64:push-r0)
    (push-register . ,riscv64:push-register)
    (quad-r0->r1-mem . ,riscv64:r0->r1-mem)
    (r+r . ,riscv64:r+r)
    (r+value . ,riscv64:r+value)
    (r->arg . ,riscv64:r->arg)
    (r->byte-label . ,riscv64:r->byte-label)
    (r->label . ,riscv64:r->label)
    (r->local . ,riscv64:r->local)
    (r->local+n . ,riscv64:r->local+n)
    (r->long-label . ,riscv64:r->long-label)
    (r->word-label . ,riscv64:r->word-label)
    (r-and . ,riscv64:r-and)
    (r-byte-mem-add . ,riscv64:r-byte-mem-add)
    (r-cmp-value . ,riscv64:r-cmp-value)
    (r-long-mem-add . ,riscv64:r-long-mem-add)
    (r-mem-add . ,riscv64:r-mem-add)
    (r-negate . ,riscv64:r-negate)
    (r-word-mem-add . ,riscv64:r-word-mem-add)
    (r-zero? . ,riscv64:r-zero?)
    (r0%r1 . ,riscv64:r0%r1)
    (r0*r1 . ,riscv64:r0*r1)
    (r0+r1 . ,riscv64:r0+r1)
    (r0+value . ,riscv64:r0+value)
    (r0->r1 . ,riscv64:r0->r1)
    (r0->r1-mem . ,riscv64:r0->r1-mem)
    (r0-and-r1 . ,riscv64:r0-and-r1)
    (r0-cmp-r1 . ,riscv64:r0-cmp-r1)
    (r0-mem->r1-mem . ,riscv64:r0-mem->r1-mem)
    (r0-or-r1 . ,riscv64:r0-or-r1)
    (r0-r1 . ,riscv64:r0-r1)
    (r0-xor-r1 . ,riscv64:r0-xor-r1)
    (r0/r1 . ,riscv64:r0/r1)
    (r0<<r1 . ,riscv64:r0<<r1)
    (r0>>r1 . ,riscv64:r0>>r1)
    (r0>>r1-signed . ,riscv64:r0>>r1-signed)
    (r1->r0 . ,riscv64:r1->r0)
    (r2->r0 . ,riscv64:r2->r0)
    (ret . ,riscv64:ret)
    (return->r . ,riscv64:return->r)
    (shl-r . ,riscv64:shl-r)
    (swap-r-stack . ,riscv64:swap-r-stack)
    (swap-r0-r1 . ,riscv64:swap-r0-r1)
    (swap-r1-stack . ,riscv64:swap-r1-stack)
    (test-r . ,riscv64:test-r)
    (value->r . ,riscv64:value->r)
    (value->r0 . ,riscv64:value->r0)
    (word-mem->r . ,riscv64:word-mem->r)
    (word-r . ,riscv64:word-r)
    (word-r->local+n . ,riscv64:word-r->local+n)
    (word-r0->r1-mem . ,riscv64:word-r0->r1-mem)
    (word-r0-mem->r1-mem . ,riscv64:word-r0-mem->r1-mem)
    (word-signed-r . ,riscv64:word-signed-r)
    (xor-zf . ,riscv64:xor-zf)
    (zf->r . ,riscv64:zf->r)
    ))
