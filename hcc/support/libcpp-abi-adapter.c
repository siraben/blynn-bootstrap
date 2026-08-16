/* Adapt HCC's address-based aggregate convention to the host SysV ABI.

   Most of GCC's libcpp interface uses scalar and pointer values.  These two
   entry points exchange cpp_num, which is a 24-byte aggregate on amd64.  HCC
   passes aggregate values by address; the host-built libcpp follows the SysV
   memory-class convention.  Keep that boundary explicit until HCC models the
   complete target ABI classification algorithm.  */

#include "config.h"
#include "system.h"

#define cpp_interpret_integer hcc_decl_cpp_interpret_integer
#define cpp_num_sign_extend hcc_decl_cpp_num_sign_extend
#include "cpplib.h"
#undef cpp_interpret_integer
#undef cpp_num_sign_extend

extern cpp_num hcc_host_cpp_interpret_integer(cpp_reader *,
                                               const cpp_token *,
                                               unsigned int);
extern cpp_num hcc_host_cpp_num_sign_extend(cpp_num, size_t);

void hcc_cpp_interpret_integer(cpp_num *, cpp_reader *, const cpp_token *,
                               unsigned int)
  __asm__("cpp_interpret_integer");
void hcc_cpp_num_sign_extend(cpp_num *, const cpp_num *, size_t)
  __asm__("cpp_num_sign_extend");

void
hcc_cpp_interpret_integer(cpp_num *result, cpp_reader *reader,
                          const cpp_token *token, unsigned int flags)
{
  *result = hcc_host_cpp_interpret_integer(reader, token, flags);
}

void
hcc_cpp_num_sign_extend(cpp_num *result, const cpp_num *number,
                        size_t precision)
{
  *result = hcc_host_cpp_num_sign_extend(*number, precision);
}
