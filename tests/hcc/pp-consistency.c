# define CONSISTENCY_FLAG 1
# define CONSISTENCY_FUNC(x) x

# ifdef CONSISTENCY_FUNC
# include "pp-consistency-include.h"
# else
# define CONSISTENCY_VALUE 0
# endif

# ifdef CONSISTENCY_VALUE
int consistency_value = CONSISTENCY_VALUE;
# else
int consistency_value = missing_consistency_value;
# endif

# if CONSISTENCY_VALUE == 7
int consistency_branch = 1;
# else
int consistency_branch = missing_consistency_branch;
# endif
