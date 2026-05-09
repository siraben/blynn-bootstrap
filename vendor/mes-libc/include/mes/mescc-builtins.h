/* -*-comment-start: "//";comment-end:""-*-
 * GNU Mes --- Maxwell Equations of Software
 * Copyright © 2022,2023 Timothy Sample <samplet@ngyro.com>
 * Copyright © 2023 Janneke Nieuwenhuizen <janneke@gnu.org>
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

struct scm *getpid_ ();
struct scm *environ_ (struct scm *args);
struct scm *opendir_ (struct scm *args);
struct scm *closedir_ (struct scm *args);
struct scm *readdir_ (struct scm *args);
struct scm *pipe_ ();
struct scm *close_port (struct scm *port);
struct scm *seek (struct scm *port, struct scm *offset, struct scm *whence);
struct scm *chdir_ (struct scm *file_name);
struct scm *stat_ (struct scm *args);
struct scm *lstat_ (struct scm *args);
struct scm *rename_file (struct scm *old_name, struct scm *new_name);
struct scm *mkdir_ (struct scm *file_name);
struct scm *rmdir_ (struct scm *file_name);
struct scm *link_ (struct scm *old_name, struct scm *new_name);
struct scm *symlink_ (struct scm *old_name, struct scm *new_name);
struct scm *umask_ (struct scm *mode);
struct scm *utime_ (struct scm *file_name, struct scm *actime, struct scm *modtime);
struct scm *sleep_ (struct scm *seconds);
