#!/bin/bash
#
# Install the "US Intl - TR" XKB layout system-wide.
#
#   ./install.sh                  validate, install, register, switch us -> ustr
#   ./install.sh --no-configure   install and register only, leave my layout list alone
#   ./install.sh --register-only  re-add the rules-registry entries (used by the apt hook)
#
# Re-runnable: every step is idempotent.

set -euo pipefail

LAYOUT=ustr
DESC="English (US, Turkish letters, AltGr)"
SHORT=ustr

XKB_DIR=/usr/share/X11/xkb
RULES_DIR="$XKB_DIR/rules"
SYMBOLS_DEST="$XKB_DIR/symbols/$LAYOUT"
BACKUP_EXT=.ustr-backup

HERE=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
SYMBOLS_SRC="$HERE/symbols/$LAYOUT"

do_install=1
do_configure=1
child=0            # set when we re-exec ourselves under sudo

while [ $# -gt 0 ]; do
    case $1 in
        --register-only) do_install=0; do_configure=0 ;;
        --no-configure)  do_configure=0 ;;
        --_child)        child=1; do_configure=0 ;;
        -h|--help)       sed -n '3,10p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

say()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- validation

# xkbcomp exits 0 even when it prints "Error:", so check both.
validate() {
    local tmp err
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN

    [ -f "$SYMBOLS_SRC" ] || die "missing $SYMBOLS_SRC"
    mkdir -p "$tmp/symbols"
    cp "$SYMBOLS_SRC" "$tmp/symbols/$LAYOUT"

    printf 'xkb_keymap {\n  xkb_keycodes { include "evdev+aliases(qwerty)" };\n  xkb_types    { include "complete" };\n  xkb_compat   { include "complete" };\n  xkb_symbols  { include "pc+%s+inet(evdev)" };\n  xkb_geometry { include "pc(pc104)" };\n};\n' "$LAYOUT" \
        | xkbcomp -I"$tmp" -w 0 -o "$tmp/test.xkm" - 2>"$tmp/err" || true

    if ! [ -s "$tmp/test.xkm" ] || grep -q '^Error:' "$tmp/err"; then
        say "$SYMBOLS_SRC does not compile:"
        sed 's/^/  /' "$tmp/err" >&2
        exit 1
    fi
    say "layout compiles cleanly"
}

# ------------------------------------------------------------ privileged part

# Always refresh the backup. We are only called for a file that does not yet
# contain our entry, so this is a pristine copy - and it must be refreshed,
# otherwise an xkb-data upgrade followed by --register-only would leave a stale
# backup that uninstall.sh would later restore over the newer package file.
snapshot() {
    local f=$1
    cp -p "$f" "$f$BACKUP_EXT"
}

# Rewrite $1 in place from stdin, keeping its owner and mode.
rewrite() {
    local f=$1 tmp
    tmp=$(mktemp)
    cat > "$tmp"
    cat "$tmp" > "$f"
    rm -f "$tmp"
}

register_xml() {
    local f=$1
    [ -f "$f" ] || return 0
    if grep -q "<name>$LAYOUT</name>" "$f"; then
        say "  $f: already registered"
        return 0
    fi
    snapshot "$f"
    awk -v layout="$LAYOUT" -v short="$SHORT" -v desc="$DESC" '
        /<\/layoutList>/ && !done {
            print "    <layout>"
            print "      <configItem>"
            print "        <name>" layout "</name>"
            print "        <shortDescription>" short "</shortDescription>"
            print "        <description>" desc "</description>"
            print "        <countryList><iso3166Id>US</iso3166Id></countryList>"
            print "        <languageList><iso639Id>eng</iso639Id><iso639Id>tur</iso639Id></languageList>"
            print "      </configItem>"
            print "      <variantList/>"
            print "    </layout>"
            done = 1
        }
        { print }
    ' "$f" | rewrite "$f"
    say "  $f: registered"
}

# Append to the "! layout" section, just after its last entry.
register_lst() {
    local f=$1 entry
    [ -f "$f" ] || return 0
    if grep -qE "^[[:space:]]+$LAYOUT[[:space:]]" "$f"; then
        say "  $f: already registered"
        return 0
    fi
    snapshot "$f"
    entry=$(printf '  %-16s%s' "$LAYOUT" "$DESC")
    awk -v entry="$entry" '
        { a[NR] = $0 }
        END {
            start = 0; stop = 0
            for (i = 1; i <= NR; i++) {
                if (a[i] ~ /^! layout/) { start = i; continue }
                if (start && a[i] ~ /^!/)  { stop = i; break }
            }
            if (!start) { for (i = 1; i <= NR; i++) print a[i]; exit }
            if (!stop) stop = NR + 1
            ins = stop - 1
            while (ins > start && a[ins] ~ /^[ \t]*$/) ins--
            for (i = 1; i <= NR; i++) { print a[i]; if (i == ins) print entry }
        }
    ' "$f" | rewrite "$f"
    say "  $f: registered"
}

privileged() {
    if [ "$do_install" -eq 1 ]; then
        install -m 0644 -o root -g root "$SYMBOLS_SRC" "$SYMBOLS_DEST"
        say "installed $SYMBOLS_DEST"
    fi
    say "registering in the rules registry:"
    register_xml "$RULES_DIR/evdev.xml"
    register_lst "$RULES_DIR/evdev.lst"
    register_xml "$RULES_DIR/base.xml"
    register_lst "$RULES_DIR/base.lst"
}

# ------------------------------------------------------- user-side configuration

# Run a command as the human who invoked us, whether or not we are root.
as_user() {
    if [ "$(id -u)" -eq 0 ]; then
        runuser -u "$TARGET_USER" -- env \
            DISPLAY="${DISPLAY:-}" XAUTHORITY="${XAUTHORITY:-}" "$@"
    else
        "$@"
    fi
}

configure() {
    local home rc list new

    TARGET_USER=${SUDO_USER:-$(id -un)}
    if [ "$TARGET_USER" = root ]; then
        warn "cannot tell which user to configure; skipping (use --no-configure to silence)"
        return 0
    fi
    home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    rc="$home/.config/kxkbrc"

    if [ ! -f "$rc" ]; then
        warn "no $rc; add the layout yourself in System Settings > Input Devices > Keyboard"
        return 0
    fi

    list=$(sed -n '/^\[Layout\]/,/^\[/p' "$rc" | sed -n 's/^LayoutList=//p' | head -1)
    case ",$list," in
        *",$LAYOUT,"*)
            say "kxkbrc already uses $LAYOUT (LayoutList=$list)" ;;
        *",us,"*)
            new=$(printf '%s' ",$list," | sed "s/,us,/,$LAYOUT,/" | sed 's/^,//; s/,$//')
            cp -p "$rc" "$rc$BACKUP_EXT"
            as_user kwriteconfig5 --file kxkbrc --group Layout --key LayoutList "$new"
            say "kxkbrc: LayoutList $list -> $new (backup at $rc$BACKUP_EXT)"
            list=$new ;;
        *)
            warn "kxkbrc LayoutList is '$list' - no 'us' entry to replace, leaving it alone"
            return 0 ;;
    esac

    # Apply to the running session too, so there is no need to log out.
    if [ -n "${DISPLAY:-}" ]; then
        local variants options
        local -a args=(-layout "$list")
        variants=$(sed -n '/^\[Layout\]/,/^\[/p' "$rc" | sed -n 's/^VariantList=//p' | head -1)
        options=$(sed -n '/^\[Layout\]/,/^\[/p' "$rc" | sed -n 's/^Options=//p' | head -1)
        if [ -n "$variants" ]; then args+=(-variant "$variants"); fi
        if [ -n "$options" ];  then args+=(-option "$options");  fi
        if as_user setxkbmap "${args[@]}"; then
            say "applied to the current session"
        else
            warn "could not apply to the running session; log out and back in"
        fi
    else
        say "no DISPLAY - the new layout takes effect at your next login"
    fi

    say "if KDE reverts it, toggle the layout list once in"
    say "System Settings > Input Devices > Keyboard > Layouts"
}

# ----------------------------------------------------------------------- main

if [ "$do_install" -eq 1 ] && [ "$child" -eq 0 ]; then
    validate
fi

if [ "$(id -u)" -eq 0 ]; then
    privileged
else
    sudo -- "$(readlink -f -- "$0")" --_child \
        $([ "$do_install" -eq 1 ] || echo --register-only)
fi

if [ "$do_configure" -eq 1 ]; then
    configure
fi

if [ "$child" -eq 0 ]; then
    say
    say "done. The layout appears as \"$DESC\"."
    say "Note: evdev.xml/base.xml belong to the xkb-data package - re-run this script"
    say "after an xkb-data upgrade, or install linux/apt-hook/99-ustr-xkb to automate it."
fi
