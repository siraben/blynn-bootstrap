#ifndef PP_CONSISTENCY_INCLUDE_H
# define PP_CONSISTENCY_INCLUDE_H

# if defined(CONSISTENCY_FLAG) && !defined(CONSISTENCY_OFF)
#  define CONSISTENCY_VALUE 7
# else
#  define CONSISTENCY_VALUE 3
# endif

#endif
