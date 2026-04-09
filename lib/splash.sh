# splash.sh — ASCII art splash screen for ralph.
#
# The character runs inside the hamster wheel. Art lives in
# templates/splash.txt so it can be edited without touching shell code.

show_splash() {
    cat "$TEMPLATES_DIR/splash.txt"
}
