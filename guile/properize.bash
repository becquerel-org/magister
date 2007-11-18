#
# properize.bash
#
# This is the hook used by properize to implement atomic resume
# of installation consistency operations.
#
STATE_DIR=$(guile -l /etc/properize.conf -c '(display *state-dir*)')