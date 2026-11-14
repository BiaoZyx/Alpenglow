#!/bin/sh
# Alpenglow prompt — BusyBox ash compatible

[ -n "$PS1" ] || return 0 2>/dev/null || exit 0

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
set -o pipefail 2>/dev/null || true

export HISTFILE="$HOME/.ash_history"
export HISTSIZE=2000

__AG_HOST=${HOSTNAME:-$(hostname 2>/dev/null || echo alpenglow)}
__AG_P=$(printf '\001\033[38;5;135m\002')
__AG_P2=$(printf '\001\033[38;5;141m\002')
__AG_P3=$(printf '\001\033[38;5;99m\002')
__AG_G=$(printf '\001\033[38;5;171m\002')
__AG_OK=$(printf '\001\033[38;5;120m\002')
__AG_ERR=$(printf '\001\033[38;5;204m\002')
__AG_R=$(printf '\001\033[0m\002')

__AG_SYM='$'
[ "$(id -u)" -eq 0 ] && __AG_SYM='#'

__ag_fold_path() {
    local p="$PWD"
    case "$p" in
        "$HOME"*) p="~${p#$HOME}" ;;
    esac
    [ -z "$p" ] && { printf '/'; return; }

    local out="" rest="$p" seg n=0 i=0 tmp
    tmp="${rest#/}"
    while [ -n "$tmp" ]; do
        case "$tmp" in
            */*) n=$((n+1)); tmp="${tmp#*/}" ;;
            *)   n=$((n+1)); tmp="" ;;
        esac
    done
    [ "$n" -eq 0 ] && { printf '/'; return; }

    rest="${rest#/}"
    while [ -n "$rest" ]; do
        case "$rest" in
            */*) seg="${rest%%/*}"; rest="${rest#*/}" ;;
            *)   seg="$rest"; rest="" ;;
        esac
        i=$((i+1))
        if [ "$seg" = "~" ] && [ $i -eq 1 ]; then
            out="~"
        elif [ $i -eq $n ]; then
            out="$out/$seg"
        else
            out="$out/${seg%"${seg#?}"}"
        fi
    done
    [ -z "$out" ] && out="/"
    printf '%s' "$out"
}

__ag_git() {
    command -v git >/dev/null 2>&1 || return
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return

    local branch status
    branch=$(git symbolic-ref --short HEAD 2>/dev/null) || \
        branch=$(git rev-parse --short HEAD 2>/dev/null) || return
    status=$(git status --porcelain=v1 --branch 2>/dev/null) || return

    local ahead=0 behind=0 added=0 staged_mod=0 unstaged_mod=0 deleted=0 untracked=0 line
    set -f
    local old_ifs="$IFS"
    IFS='
'
    set -- $status
    IFS="$old_ifs"
    set +f

    for line in "$@"; do
        case "$line" in
            '## '*)
                case "$line" in
                    *'[ahead '*) ahead="${line#*\[ahead }"; ahead="${ahead%%]*}" ;;
                esac
                case "$line" in
                    *'behind '*) behind="${line#*behind }"; behind="${behind%%]*}" ;;
                esac
                ;;
            '?? '*)              untracked=$((untracked+1)) ;;
            'A  '*)              added=$((added+1)) ;;
            'AM '*)              added=$((added+1)); unstaged_mod=$((unstaged_mod+1)) ;;
            'AD '*)              added=$((added+1)); unstaged_mod=$((unstaged_mod+1)) ;;
            'M  '*)              staged_mod=$((staged_mod+1)) ;;
            'MM '*)              staged_mod=$((staged_mod+1)); unstaged_mod=$((unstaged_mod+1)) ;;
            'MD '*)              staged_mod=$((staged_mod+1)); unstaged_mod=$((unstaged_mod+1)) ;;
            ' M '*)              unstaged_mod=$((unstaged_mod+1)) ;;
            ' D '*)              unstaged_mod=$((unstaged_mod+1)) ;;
            'D  '*)              deleted=$((deleted+1)) ;;
            'DM '*)              deleted=$((deleted+1)); unstaged_mod=$((unstaged_mod+1)) ;;
            'DD '*)              deleted=$((deleted+1)); unstaged_mod=$((unstaged_mod+1)) ;;
        esac
    done

    local out=""
    [ -n "$ahead" ]  && [ "$ahead" != "0" ]  && out="$out ${__AG_G}[ahead]${__AG_R}${ahead}"
    [ -n "$behind" ] && [ "$behind" != "0" ] && out="$out ${__AG_ERR}[behind]${__AG_R}${behind}"
    [ $added -gt 0 ]        && out="$out ${__AG_OK}+${added}${__AG_R}"
    [ $staged_mod -gt 0 ]   && out="$out ${__AG_P2}!${staged_mod}${__AG_R}"
    [ $deleted -gt 0 ]      && out="$out ${__AG_ERR}-${deleted}${__AG_R}"
    [ $unstaged_mod -gt 0 ] && out="$out ${__AG_P2}~${unstaged_mod}${__AG_R}"
    [ $untracked -gt 0 ]    && out="$out ${__AG_P3}?${untracked}${__AG_R}"

    printf '(%s%s%s)' "$__AG_G" "$branch" "$__AG_R"
    printf '%s' "$out"
}

__ag_prompt() {
    local path git user
    user=${USER:-$(id -un 2>/dev/null || echo root)}
    path=$(__ag_fold_path)
    git=$(__ag_git)
    printf '%s%s%s@%s%s%s:%s%s%s%s %s ' \
        "$__AG_P" "$user" "$__AG_R" \
        "$__AG_P2" "$__AG_HOST" "$__AG_R" \
        "$__AG_P3" "$path" "$__AG_R" \
        "$git" "$__AG_SYM"
}

PS1='${__AG_G}[$?]${__AG_R}$(__ag_prompt)'

# aliases
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ls='ls --color=auto'
alias l='ls -lAh'
alias ll='ls -l'
alias la='ls -A'
alias grep='grep --color=auto'
alias g='git'
alias gst='git status'
alias gp='git pull'
alias gpu='git push'
alias gc='git commit'
alias gd='git diff'
alias gl='git log --oneline --graph'

mkcd() { [ -n "$1" ] || { echo "usage: mkcd <dir>" >&2; return 1; }; mkdir -p "$1" && cd "$1"; }

extract() {
    [ -f "$1" ] || { echo "extract: no such file: $1" >&2; return 1; }
    case "$1" in
        *.tar.gz|*.tgz) tar xzf "$1" ;;
        *.tar.xz)       tar xJf "$1" ;;
        *.tar.bz2)      tar xjf "$1" ;;
        *.zip)          unzip "$1" ;;
        *.gz)           gunzip "$1" ;;
        *)              echo "extract: unknown format: $1" >&2; return 1 ;;
    esac
}

backup() {
    [ -n "$1" ] || { echo "usage: backup <target-dir>" >&2; return 1; }
    [ -d "$1" ] && [ -w "$1" ] || { echo "backup: cannot write to $1" >&2; return 1; }
    local ts out
    ts=$(date +%Y%m%d-%H%M%S)
    out="$1/alpenglow-$ts.tar.gz"
    ( cd / && tar czf "$out" "${HOME#/}" etc 2>/dev/null )
    echo "$out"
}
