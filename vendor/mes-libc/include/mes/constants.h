/* -*-comment-start: "//";comment-end:""-*-
 * GNU Mes --- Maxwell Equations of Software
 * Copyright © 2016,2017,2018,2019,2022 Jan (janneke) Nieuwenhuizen <janneke@gnu.org>
 *
 * This file is part of GNU Mes.
 *
 * GNU Mes is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or (at
 * your option) any later version.
 *
 * GNU Mes is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with GNU Mes.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef __MES_CONSTANTS_H
#define __MES_CONSTANTS_H

/* Cell types */

#define TCHAR              0

#define TBYTES             1
#define TCLOSURE           2
#define TCONTINUATION      3
#define TKEYWORD           4
#define TMACRO             5
#define TNUMBER            6
#define TPAIR              7
#define TPORT              8
#define TREF               9
#define TSPECIAL          10
#define TSTRING           11
#define TSTRUCT           12
#define TSYMBOL           13
#define TVALUES           14
#define TBINDING          15
#define TVECTOR           16
#define TBROKEN_HEART     17

/* Struct types */

#define STRUCT_TYPE 0
#define STRUCT_PRINTER 1

#define GC_FRAME_SIZE 5
#define GC_FRAME_PROCEDURE 4

#define MODULE_OBARRAY 3
#define MODULE_USES 4
#define MODULE_BINDER 5
#define MODULE_EVAL_CLOSURE 6

#endif /* __MES_CONSTANTS_H */
