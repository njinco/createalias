#!/usr/bin/env bash

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(eval echo "~$TARGET_USER")"
if [[ "$TARGET_HOME" == "~$TARGET_USER" || -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
  TARGET_HOME="$HOME"
fi

BASHRC="$TARGET_HOME/.bashrc"
BASH_ALIASES="$TARGET_HOME/.bash_aliases"

SCRIPT_SOURCED=0
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  SCRIPT_SOURCED=1
fi

USE_COLOR=0
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  USE_COLOR=1
fi

if (( USE_COLOR )); then
  C_RESET=$'\033[0m'
  C_TITLE=$'\033[1;36m'
  C_PROMPT=$'\033[1;33m'
  C_INFO=$'\033[1;32m'
  C_WARN=$'\033[1;31m'
  C_DIM=$'\033[2m'
  C_CAT=$'\033[1;34m'
  C_OUT=$'\033[0;36m'
else
  C_RESET=""
  C_TITLE=""
  C_PROMPT=""
  C_INFO=""
  C_WARN=""
  C_DIM=""
  C_CAT=""
  C_OUT=""
fi

section() {
  echo ""
  echo "${C_TITLE}== $1 ==${C_RESET}"
}

info() {
  echo "${C_INFO}$*${C_RESET}"
}

warn() {
  echo "${C_WARN}$*${C_RESET}"
}

dim() {
  echo "${C_DIM}$*${C_RESET}"
}

category() {
  echo "${C_CAT}$*${C_RESET}"
}

output_block() {
  local content="$1"
  if [[ -n "$content" ]]; then
    printf '%s%s%s\n' "$C_OUT" "$content" "$C_RESET"
  fi
}

menu_item() {
  local num="$1"
  local title="$2"
  local desc="$3"
  if [[ -n "$desc" ]]; then
    printf '%s%s)%s %s %s- %s%s\n' "$C_CAT" "$num" "$C_RESET" "$title" "$C_DIM" "$desc" "$C_RESET"
  else
    printf '%s%s)%s %s\n' "$C_CAT" "$num" "$C_RESET" "$title"
  fi
}

if [[ -n "$SUDO_USER" && "${EUID:-$(id -u)}" -eq 0 ]]; then
  info "Running as root; targeting aliases for user $TARGET_USER ($TARGET_HOME)."
fi

if [[ $SCRIPT_SOURCED -eq 0 ]]; then
  warn "This script must be sourced (not executed) to manage current shell aliases."
  info "Run: source ./crealias.sh"
  info "Or:  source /full/path/to/crealias.sh"
  exit 1
fi

SELECTED_ALIAS=""

prompt_alias_name() {
  local name
  while true; do
    read -r -p "${C_PROMPT}Alias name: ${C_RESET}" name
    if [[ -z "$name" ]]; then
      warn "Alias name cannot be empty."
      continue
    fi
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      warn "Use letters, numbers, and underscores; start with a letter or underscore."
      continue
    fi
    printf '%s' "$name"
    return 0
  done
}

prompt_alias_name_optional() {
  local name
  while true; do
    read -r -p "${C_PROMPT}Alias name (blank to go back): ${C_RESET}" name
    if [[ -z "$name" ]]; then
      return 1
    fi
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      warn "Use letters, numbers, and underscores; start with a letter or underscore."
      continue
    fi
    printf '%s' "$name"
    return 0
  done
}

prompt_alias_command() {
  local cmd
  while true; do
    read -r -p "${C_PROMPT}Alias command/path: ${C_RESET}" cmd
    if [[ -z "$cmd" ]]; then
      warn "Command/path cannot be empty."
      continue
    fi
    printf '%s' "$cmd"
    return 0
  done
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-}"
  local answer
  while true; do
    read -r -p "${C_PROMPT}${prompt}${C_RESET}" answer
    if [[ -z "$answer" && -n "$default" ]]; then
      answer="$default"
    fi
    case "$answer" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      *) warn "Please enter y or n." ;;
    esac
  done
}

choose_target() {
  local choice
  category "Save alias to:"
  menu_item 1 "~/.bashrc" "main shell config"
  menu_item 2 "~/.bash_aliases" "dedicated aliases file"
  menu_item 3 "Both" "write to both files"
  while true; do
    read -r -p "${C_PROMPT}Select [1-3]: ${C_RESET}" choice
    case "$choice" in
      1) echo "bashrc"; return 0 ;;
      2) echo "bash_aliases"; return 0 ;;
      3) echo "both"; return 0 ;;
      *) warn "Please choose 1, 2, or 3." ;;
    esac
  done
}

ensure_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    touch "$file"
  fi
}

ensure_bash_aliases_sourced() {
  ensure_file "$BASHRC"
  if ! grep -qE '(^|[[:space:]])(source|\.)[[:space:]]+(~|\$HOME)/\.bash_aliases' "$BASHRC"; then
    cat >> "$BASHRC" <<'EOF'

# Load ~/.bash_aliases if it exists
if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi
EOF
    info "Added ~/.bash_aliases loader to ~/.bashrc"
  fi
}

alias_in_file() {
  local name="$1"
  local file="$2"
  [[ -f "$file" ]] || return 1
  grep -Eq "^[[:space:]]*alias[[:space:]]+$name=" "$file"
}

alias_names_from_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  sed -nE 's/^[[:space:]]*alias[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' "$file"
}

alias_names_from_shell() {
  local lines
  if [[ $SCRIPT_SOURCED -eq 1 ]]; then
    lines=$(alias 2>/dev/null || true)
  else
    if [[ -n "$SUDO_USER" && "${EUID:-$(id -u)}" -eq 0 ]]; then
      lines=$(sudo -u "$TARGET_USER" -H bash -ic 'alias' 2>/dev/null || true)
    else
      lines=$(bash -ic 'alias' 2>/dev/null || true)
    fi
  fi
  printf '%s\n' "$lines" | sed -nE 's/^alias[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p'
}

select_alias_name() {
  local label="$1"
  shift
  local -a names=()
  local name
  SELECTED_ALIAS=""
  for name in "$@"; do
    [[ -n "$name" ]] && names+=("$name")
  done
  if [[ ${#names[@]} -eq 0 ]]; then
    warn "(none found)"
    return 1
  fi
  mapfile -t names < <(printf '%s\n' "${names[@]}" | sort -u)
  if [[ -n "$label" ]]; then
    category "$label"
  fi
  printf '%s0)%s %sBack%s\n' "$C_CAT" "$C_RESET" "$C_DIM" "$C_RESET"
  local i
  for i in "${!names[@]}"; do
    printf '%s%d)%s %s%s%s\n' "$C_CAT" "$((i+1))" "$C_RESET" "$C_OUT" "${names[$i]}" "$C_RESET"
  done
  local choice
  while true; do
    read -r -p "${C_PROMPT}Select: ${C_RESET}" choice
    if [[ "$choice" == "0" ]]; then
      return 1
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#names[@]} )); then
      SELECTED_ALIAS="${names[$((choice-1))]}"
      return 0
    fi
    warn "Please choose a number from the list."
  done
}

confirm_remove_action() {
  local name="$1"
  local answer
  while true; do
    read -r -p "${C_PROMPT}Remove '$name'? [y=continue, b=back, c=cancel]: ${C_RESET}" answer
    case "$answer" in
      y|Y) return 0 ;;
      b|B) return 1 ;;
      c|C) return 2 ;;
      *) warn "Please enter y, b, or c." ;;
    esac
  done
}

remove_alias_from_file() {
  local name="$1"
  local file="$2"
  [[ -f "$file" ]] || return 0
  local tmp
  tmp=$(mktemp)
  awk -v name="$name" '
    $0 ~ "^[[:space:]]*alias[[:space:]]+" name "=" {next}
    {print}
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

add_alias_to_file() {
  local name="$1"
  local cmd="$2"
  local file="$3"
  ensure_file "$file"
  if alias_in_file "$name" "$file"; then
    remove_alias_from_file "$name" "$file"
  fi
  echo "alias $name=$(printf '%q' "$cmd")" >> "$file"
}

source_bashrc() {
  if [[ $SCRIPT_SOURCED -eq 1 ]]; then
    if [[ -f "$BASHRC" ]]; then
      . "$BASHRC"
      info "Reloaded ~/.bashrc"
    fi
  else
    info "To load changes in your shell, run: source \"$BASHRC\""
  fi
}

create_alias_flow() {
  section "Create Alias"
  local name cmd target
  name=$(prompt_alias_name)
  cmd=$(prompt_alias_command)

  if alias "$name" &>/dev/null; then
    if ! ask_yes_no "Alias exists in current shell. Overwrite? [y/n]: " "n"; then
      warn "Cancelled (no changes)."
      return 0
    fi
  fi

  if ask_yes_no "Make this alias permanent? [y/n]: " "y"; then
    target=$(choose_target)
    if [[ "$target" == "bash_aliases" || "$target" == "both" ]]; then
      ensure_file "$BASH_ALIASES"
      ensure_bash_aliases_sourced
    fi
    if [[ "$target" == "bashrc" || "$target" == "both" ]]; then
      ensure_file "$BASHRC"
    fi

    if [[ "$target" == "bashrc" || "$target" == "both" ]]; then
      add_alias_to_file "$name" "$cmd" "$BASHRC"
      info "Added alias to ~/.bashrc (file)"
    fi
    if [[ "$target" == "bash_aliases" || "$target" == "both" ]]; then
      add_alias_to_file "$name" "$cmd" "$BASH_ALIASES"
      info "Added alias to ~/.bash_aliases (file)"
    fi

    source_bashrc
  else
    if [[ $SCRIPT_SOURCED -eq 1 ]]; then
      alias "$name=$(printf '%q' "$cmd")"
      info "Alias added to current shell session (session)."
    else
      warn "Temporary aliases only work when this script is sourced."
      info "Run: source ./crealias.sh"
    fi
  fi
}

list_aliases_in_file() {
  local file="$1"
  local label="$2"
  category "$label"
  if [[ -f "$file" ]]; then
    local lines
    lines=$(grep -E '^[[:space:]]*alias[[:space:]]+' "$file" | grep -vE '^[[:space:]]*#' || true)
    if [[ -n "$lines" ]]; then
      output_block "$lines"
    else
      dim "(none)"
    fi
  else
    warn "(missing)"
  fi
}

list_aliases_flow() {
  section "List Aliases"
  local lines
  if [[ $SCRIPT_SOURCED -eq 1 ]]; then
    category "Current shell aliases (active session):"
    lines=$(alias 2>/dev/null || true)
    if [[ -n "$lines" ]]; then
      output_block "$lines"
    else
      dim "(none)"
    fi
  else
    category "Current shell aliases (interactive bash):"
    dim "(script not sourced; showing aliases from a fresh interactive bash)"
    if [[ -n "$SUDO_USER" && "${EUID:-$(id -u)}" -eq 0 ]]; then
      lines=$(sudo -u "$TARGET_USER" -H bash -ic 'alias' 2>/dev/null || true)
    else
      lines=$(bash -ic 'alias' 2>/dev/null || true)
    fi
    if [[ -n "$lines" ]]; then
      output_block "$lines"
    else
      dim "(none)"
    fi
  fi
  echo ""
  list_aliases_in_file "$BASHRC" "~/.bashrc aliases (file):"
  echo ""
  list_aliases_in_file "$BASH_ALIASES" "~/.bash_aliases aliases (file):"
}

remove_alias_flow() {
  section "Remove Alias"
  local name choice
  local remove_bashrc remove_bash_aliases remove_shell did_file_remove
  local -a names

  while true; do
    category "Alias selection source:"
    menu_item 1 "Choose from ~/.bashrc" "aliases defined in ~/.bashrc"
    menu_item 2 "Choose from ~/.bash_aliases" "aliases defined in ~/.bash_aliases"
    menu_item 3 "Choose from both files" "combined file aliases"
    menu_item 4 "Choose from interactive shell aliases" "active session aliases"
    menu_item 5 "Type alias name" "manual entry"
    menu_item 6 "Back" "return to main menu"
    read -r -p "${C_PROMPT}Select [1-6]: ${C_RESET}" choice
    case "$choice" in
      1)
        mapfile -t names < <(alias_names_from_file "$BASHRC")
        if select_alias_name "Aliases in ~/.bashrc:" "${names[@]}"; then
          name="$SELECTED_ALIAS"
        else
          continue
        fi
        ;;
      2)
        mapfile -t names < <(alias_names_from_file "$BASH_ALIASES")
        if select_alias_name "Aliases in ~/.bash_aliases:" "${names[@]}"; then
          name="$SELECTED_ALIAS"
        else
          continue
        fi
        ;;
      3)
        mapfile -t names < <(alias_names_from_file "$BASHRC"; alias_names_from_file "$BASH_ALIASES")
        if select_alias_name "Aliases in ~/.bashrc and ~/.bash_aliases:" "${names[@]}"; then
          name="$SELECTED_ALIAS"
        else
          continue
        fi
        ;;
      4)
        mapfile -t names < <(alias_names_from_shell)
        if select_alias_name "Aliases in interactive shell:" "${names[@]}"; then
          name="$SELECTED_ALIAS"
        else
          continue
        fi
        ;;
      5)
        name=$(prompt_alias_name_optional) || return 0
        ;;
      6)
        return 0
        ;;
      *) warn "Please choose 1, 2, 3, 4, 5, or 6." ;;
    esac

    confirm_remove_action "$name"
    case $? in
      1) continue ;;
      2) return 0 ;;
    esac

    remove_bashrc=0
    remove_bash_aliases=0
    remove_shell=0
    did_file_remove=0

    section "Removal Targets"
    while true; do
      category "Remove from files:"
      menu_item 0 "Back" "return to alias selection"
      menu_item 1 "~/.bashrc" "remove from main shell config"
      menu_item 2 "~/.bash_aliases" "remove from aliases file"
      menu_item 3 "Both" "remove from both files"
      menu_item 4 "Skip file removal" "only affect current session"
      read -r -p "${C_PROMPT}Select [0-4]: ${C_RESET}" choice
      case "$choice" in
        0) continue 2 ;;
        1) remove_bashrc=1; break ;;
        2) remove_bash_aliases=1; break ;;
        3) remove_bashrc=1; remove_bash_aliases=1; break ;;
        4) break ;;
        *) warn "Please choose 0, 1, 2, 3, or 4." ;;
      esac
    done

    if [[ $SCRIPT_SOURCED -eq 1 ]]; then
      if alias "$name" &>/dev/null; then
        if ask_yes_no "Remove from current shell? [y/n]: " "y"; then
          remove_shell=1
        fi
      else
        warn "Alias not found in current shell (session)."
      fi
    else
      warn "Current shell aliases cannot be changed unless the script is sourced."
    fi

    if (( remove_shell == 1 )); then
      unalias "$name"
      info "Removed from current shell (session)."
    fi

    if (( remove_bashrc == 1 )); then
      if alias_in_file "$name" "$BASHRC"; then
        remove_alias_from_file "$name" "$BASHRC"
        info "Removed from ~/.bashrc (file)"
        did_file_remove=1
      else
        warn "Alias not found in ~/.bashrc (file)."
      fi
    fi

    if (( remove_bash_aliases == 1 )); then
      if alias_in_file "$name" "$BASH_ALIASES"; then
        remove_alias_from_file "$name" "$BASH_ALIASES"
        info "Removed from ~/.bash_aliases (file)"
        did_file_remove=1
      else
        warn "Alias not found in ~/.bash_aliases (file)."
      fi
    fi

    if (( remove_shell == 0 && did_file_remove == 0 )); then
      warn "No changes made (nothing selected or found)."
    fi

    if (( did_file_remove == 1 )); then
      source_bashrc
    fi
    return 0
  done
}

while true; do
  section "Alias Manager"
  menu_item 1 "Create alias" "step-by-step add (temporary or permanent)"
  menu_item 2 "List aliases" "show current session + file-based aliases"
  menu_item 3 "Remove alias" "pick from lists or type a name"
  menu_item 4 "Quit" "exit the menu"
  read -r -p "${C_PROMPT}Select [1-4]: ${C_RESET}" choice
  case "$choice" in
    1) create_alias_flow ;;
    2) list_aliases_flow ;;
    3) remove_alias_flow ;;
    4) return 0 ;;
    *) warn "Please choose 1, 2, 3, or 4." ;;
  esac
done
