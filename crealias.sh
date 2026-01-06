#!/usr/bin/env bash

BASHRC="$HOME/.bashrc"
BASH_ALIASES="$HOME/.bash_aliases"

SCRIPT_SOURCED=0
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  SCRIPT_SOURCED=1
fi

prompt_alias_name() {
  local name
  while true; do
    read -r -p "Alias name: " name
    if [[ -z "$name" ]]; then
      echo "Alias name cannot be empty."
      continue
    fi
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "Use letters, numbers, and underscores; start with a letter or underscore."
      continue
    fi
    printf '%s' "$name"
    return 0
  done
}

prompt_alias_command() {
  local cmd
  while true; do
    read -r -p "Alias command/path: " cmd
    if [[ -z "$cmd" ]]; then
      echo "Command/path cannot be empty."
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
    read -r -p "$prompt" answer
    if [[ -z "$answer" && -n "$default" ]]; then
      answer="$default"
    fi
    case "$answer" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
      *) echo "Please enter y or n." ;;
    esac
  done
}

choose_target() {
  local choice
  echo "Save alias to:"
  echo "1) ~/.bashrc"
  echo "2) ~/.bash_aliases"
  echo "3) Both"
  while true; do
    read -r -p "Select [1-3]: " choice
    case "$choice" in
      1) echo "bashrc"; return 0 ;;
      2) echo "bash_aliases"; return 0 ;;
      3) echo "both"; return 0 ;;
      *) echo "Please choose 1, 2, or 3." ;;
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
    echo "Added ~/.bash_aliases loader to ~/.bashrc"
  fi
}

alias_in_file() {
  local name="$1"
  local file="$2"
  [[ -f "$file" ]] || return 1
  grep -Eq "^[[:space:]]*alias[[:space:]]+$name=" "$file"
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
    fi
  else
    echo "To load changes in your shell, run: source \"$BASHRC\""
  fi
}

create_alias_flow() {
  local name cmd target
  name=$(prompt_alias_name)
  cmd=$(prompt_alias_command)

  if alias "$name" &>/dev/null; then
    if ! ask_yes_no "Alias exists in current shell. Overwrite? [y/n]: " "n"; then
      echo "Cancelled."
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
      echo "Added alias to ~/.bashrc"
    fi
    if [[ "$target" == "bash_aliases" || "$target" == "both" ]]; then
      add_alias_to_file "$name" "$cmd" "$BASH_ALIASES"
      echo "Added alias to ~/.bash_aliases"
    fi

    source_bashrc
  else
    if [[ $SCRIPT_SOURCED -eq 1 ]]; then
      alias "$name=$(printf '%q' "$cmd")"
      echo "Alias added to current shell session."
    else
      echo "Temporary aliases only work when this script is sourced."
      echo "Run: source ./crealias.sh"
    fi
  fi
}

list_aliases_in_file() {
  local file="$1"
  local label="$2"
  echo "$label"
  if [[ -f "$file" ]]; then
    local lines
    lines=$(grep -E '^[[:space:]]*alias[[:space:]]+' "$file" | grep -vE '^[[:space:]]*#' || true)
    if [[ -n "$lines" ]]; then
      echo "$lines"
    else
      echo "(none)"
    fi
  else
    echo "(missing)"
  fi
}

list_aliases_flow() {
  echo "Current shell aliases:"
  if [[ $SCRIPT_SOURCED -eq 1 ]]; then
    alias || echo "(none)"
  else
    echo "(not available when executed as a script)"
  fi
  echo ""
  list_aliases_in_file "$BASHRC" "~/.bashrc aliases:"
  echo ""
  list_aliases_in_file "$BASH_ALIASES" "~/.bash_aliases aliases:"
}

remove_alias_flow() {
  local name choice
  name=$(prompt_alias_name)

  if [[ $SCRIPT_SOURCED -eq 1 ]]; then
    if alias "$name" &>/dev/null; then
      if ask_yes_no "Remove from current shell? [y/n]: " "y"; then
        unalias "$name"
        echo "Removed from current shell."
      fi
    else
      echo "Alias not found in current shell."
    fi
  else
    echo "Current shell aliases cannot be changed unless the script is sourced."
  fi

  echo "Remove from:"
  echo "1) ~/.bashrc"
  echo "2) ~/.bash_aliases"
  echo "3) Both"
  echo "4) Skip file removal"
  while true; do
    read -r -p "Select [1-4]: " choice
    case "$choice" in
      1)
        if alias_in_file "$name" "$BASHRC"; then
          remove_alias_from_file "$name" "$BASHRC"
          echo "Removed from ~/.bashrc"
        else
          echo "Alias not found in ~/.bashrc"
        fi
        break
        ;;
      2)
        if alias_in_file "$name" "$BASH_ALIASES"; then
          remove_alias_from_file "$name" "$BASH_ALIASES"
          echo "Removed from ~/.bash_aliases"
        else
          echo "Alias not found in ~/.bash_aliases"
        fi
        break
        ;;
      3)
        if alias_in_file "$name" "$BASHRC"; then
          remove_alias_from_file "$name" "$BASHRC"
          echo "Removed from ~/.bashrc"
        else
          echo "Alias not found in ~/.bashrc"
        fi
        if alias_in_file "$name" "$BASH_ALIASES"; then
          remove_alias_from_file "$name" "$BASH_ALIASES"
          echo "Removed from ~/.bash_aliases"
        else
          echo "Alias not found in ~/.bash_aliases"
        fi
        break
        ;;
      4)
        echo "Skipped file removal."
        break
        ;;
      *) echo "Please choose 1, 2, 3, or 4." ;;
    esac
  done

  source_bashrc
}

while true; do
  echo ""
  echo "Alias Manager"
  echo "1) Create alias"
  echo "2) List aliases"
  echo "3) Remove alias"
  echo "4) Quit"
  read -r -p "Select [1-4]: " choice
  case "$choice" in
    1) create_alias_flow ;;
    2) list_aliases_flow ;;
    3) remove_alias_flow ;;
    4) exit 0 ;;
    *) echo "Please choose 1, 2, 3, or 4." ;;
  esac
done
