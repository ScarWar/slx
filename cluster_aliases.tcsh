# Cluster management aliases for tcsh
# Source this file in your .tcshrc or run: source cluster_aliases.tcsh
# 
# To add permanently, add this line to your ~/.tcshrc:
#   source $HOME/workdir/cluster_aliases.tcsh
#
# You can override the workdir by setting CLUSTER_WORKDIR before sourcing:
#   setenv CLUSTER_WORKDIR /path/to/workdir
#   source $CLUSTER_WORKDIR/cluster_aliases.tcsh

# Set cluster script directory (defaults to $HOME/workdir)
if ( ! $?CLUSTER_WORKDIR ) then
    setenv CLUSTER_WORKDIR $HOME/workdir
endif
set CLUSTER_DIR = $CLUSTER_WORKDIR

# Base command
alias c '$CLUSTER_DIR/bin/cluster.sh'

# Submit jobs
alias cs '$CLUSTER_DIR/bin/cluster.sh submit'

# View logs
alias cl '$CLUSTER_DIR/bin/cluster.sh logs'

# List jobs
alias cls '$CLUSTER_DIR/bin/cluster.sh list'

# Running jobs
alias cr '$CLUSTER_DIR/bin/cluster.sh running'

# Pending jobs (renamed from 'cp' to avoid conflict with copy command)
alias cpd '$CLUSTER_DIR/bin/cluster.sh pending'

# Kill job
alias ck '$CLUSTER_DIR/bin/cluster.sh kill'

# Kill all jobs
alias cka '$CLUSTER_DIR/bin/cluster.sh killall'

# Tail logs
alias ct '$CLUSTER_DIR/bin/cluster.sh tail'

# Job info
alias ci '$CLUSTER_DIR/bin/cluster.sh info'

# Status summary
alias cst '$CLUSTER_DIR/bin/cluster.sh status'

# History
alias ch '$CLUSTER_DIR/bin/cluster.sh history'

# Find jobs
alias cf '$CLUSTER_DIR/bin/cluster.sh find'

# Clean logs (renamed from 'cc' to avoid conflict with C compiler)
alias ccl '$CLUSTER_DIR/bin/cluster.sh clean'
