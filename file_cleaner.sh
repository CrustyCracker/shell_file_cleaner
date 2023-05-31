#!/bin/bash

X_DIR="./X"     
YES_ANY=0       
VERBOSE=0       

declare -a SOURCE
declare -a TASK_LIST   
declare -a DUPLICATED_FILES_BATCH

OLDEST_FILE=""
OLDEST_FILE_DATE=""

source ./.file_cleaner_config

printstate () {
    echo X_DIR = $X_DIR
    echo SOURCE = ${SOURCE[@]}
    echo TASK_LIST = ${TASK_LIST[@]}
    echo YES_ANY = $YES_ANY
}


exe_help () {
    cat << EOF
Usage: sh file_cleaner.sh [FLAGS] DIRS_WHERE_THE_FILES_ARE
    FLAGS:
    -x, --set_dir       Specify the directory X where all the files should be moved/copied 
    -m, --move          Move files to the target directory X
    -c, --copy          Copy files to the target directory X
    -r, --rename        Enable renaming of all affected files
    -e, --remove-empty  Remove empty files
    -t, --remove-tmp    Remove temporary files
    -n, --keep-newest   Keep the newest file among the files with the same name
    -d, --remove-dups   Remove duplicate files based on their content
    -p, --default-perms Set permissions to default values (644)
    -s, --swap-text     swap text symbols TEXT_TO_SWAP defined in .file_cleaner_config to the SYMBOL_TO_SWAP_TO
    -v, --verbose       Print detailed information about what the program is doing
    -y, --yes-any       Do not ask for confirmation before executing any action 
    -h, --help          Display this help message
    Note: Options -s and -p require root access
EOF
    exit 0;
}


while test $# -gt 0
do
    case $1 in
        -h | --help)
            exe_help
            ;;
        -x | --set_dir)
            X_DIR=$2
            shift
            shift
            ;;
        -d | --remove-dups)
            TASK_LIST+=("REMOVE_DUPS")
            shift
            ;;
        -e | --remove-empty)
            TASK_LIST+=("REMOVE_EMPTY")
            shift
            ;;
        -t | --remove-tmp)
            TASK_LIST+=("REMOVE_TMP")
            shift
            ;;
        -n | --keep-newest)
            TASK_LIST+=("KEEP_NEWEST")
            shift
            ;;
        -m | --move)
            TASK_LIST+=("MOVE")
            shift
            ;;
        -c | --copy)
            TASK_LIST+=("COPY")
            shift
            ;;
        -p | --default-perms)
            TASK_LIST+=("DEFAULT_PERMS")
            shift
            ;;
        -s | --swap-text)
            TASK_LIST+=("SWAP_TEXT")
            shift
            ;;
        -r | --rename)
            TASK_LIST+=("RENAME")
            shift
            ;;
        -y | --yes-any)
            YES_ANY=1
            shift
            ;;
        -v | --verbose)
            VERBOSE=1
            shift
            ;;
        -*)
            echo "Invalid option $1" 1>&2  
            exe_help
            ;;
        *)
            SOURCE+=("$1")
            shift;
            ;;
    esac
done



declare -a DUPLICATED_FILES_BATCH
OLDEST_FILE=""
OLDEST_FILE_DATE=""

find_oldest() {
  OLDEST_FILE="${DUPLICATED_FILES_BATCH[0]}"
  OLDEST_FILE_DATE=$(stat -c %Y "$OLDEST_FILE")

  for ((i = 1; i < ${#DUPLICATED_FILES_BATCH[@]}; i++)); do
    local F="${DUPLICATED_FILES_BATCH[$i]}"
    local F_TIME=$(stat -c %Y "$F")

    if (( F_TIME < OLDEST_FILE_DATE )); then
      OLDEST_FILE=$F
      OLDEST_FILE_DATE=$F_TIME
    fi
  done
}

exe_duplicates() {
  [[ -z $CURRENT_HASH ]] && return

  local OLDEST_COMMAND="-gt"
  if (( VERBOSE == 1 )); then
    echo "Batch of the same files found: ${DUPLICATED_FILES_BATCH[*]}..."
    find_oldest
    echo "Found the oldest file in batch: $OLDEST_FILE..."
  else
    find_oldest
  fi

  if (( YES_ANY == 1 )); then
    for ((i = 0; i < ${#DUPLICATED_FILES_BATCH[@]}; i++)); do
      local F="${DUPLICATED_FILES_BATCH[$i]}"
      if [[ "$F" != "$OLDEST_FILE" ]]; then
        if (( VERBOSE == 1 )); then
          echo "Removing duplicate: $F..."
        fi
        rm -f "$F"
      fi
    done
  else
    for ((i = 0; i < ${#DUPLICATED_FILES_BATCH[@]}; i++)); do
      local F="${DUPLICATED_FILES_BATCH[$i]}"
      if [[ "$F" != "$OLDEST_FILE" ]]; then
        read -p "Remove duplicate: $FILE? (y/n) " ANSWER </dev/tty
        if [[ "$ANSWER" == 'y' ]]; then
          rm -f "$F"
        fi
      fi
    done
  fi
}

do_duplicates() {
  find "${SOURCE[@]}" ! -empty -type f -exec md5sum {} + |
    sort |
    uniq -w32 -dD |
    {
      CURRENT_HASH=""

      while IFS= read -r -d $'\n' LINE; do
        local HASH=$(echo "$LINE" | cut -c 1-32)
        local FILE=$(echo "$LINE" | cut -c 35-)

        if [[ "$HASH" == "$CURRENT_HASH" ]]; then
          DUPLICATED_FILES_BATCH+=("$FILE")
        else
          exe_duplicates
          CURRENT_HASH="$HASH"
          DUPLICATED_FILES_BATCH=("$FILE")
        fi
      done
      exe_duplicates
    }
}

do_empty() {
    while IFS= read -r -d '' file; do
        if [[ ! -s "$file" ]]; then
            if [[ "$YES_ANY" -eq 1 ]]; then
                [[ "$VERBOSE" -eq 1 ]] && echo "Removing empty file: $file..."
                rm -f "$file"
            else
                read -p "Remove empty file: $file? (y/n) " answer </dev/tty
                [[ "$answer" = "y" ]] && rm -f "$file"
            fi
        fi
    done < <(find "${SOURCE[@]}" -type f -size 0 -print0)
}

do_remove_tmp() {
    while IFS= read -r -d '' FILE; do
        if [[ -f "$FILE" ]]; then
            if [[ $YES_ANY -eq 1 ]]; then
                if [[ $VERBOSE -eq 1 ]]; then
                    echo "Removing temporary file: $FILE..."
                fi
                rm -f "$FILE"
            else
                read -p "Remove temporary file: $FILE? (y/n) " ANSWER </dev/tty
                if [[ "$ANSWER" = "y" ]]; then
                    rm -f "$FILE"
                fi
            fi
        fi
    done < <(find "${SOURCE[@]}" -type f -regex "$TMP_FILES" -print0)
}
do_keep_newest() {
  find "${SOURCE[@]}" -type f -print0 |

    sed 's_.*/__' -z |
    sort -z |

    uniq -z -d | while IFS= read -r -d $'\0' KEEP_NEWEST; do

      find "${SOURCE[@]}" -name "$KEEP_NEWEST" -print0 | {

        readarray -t KEEP_NEWEST_FILE_BATCH

        YOUNGEST_FILE="$(stat -c '%Y %n' "${KEEP_NEWEST_FILE_BATCH[@]}" | sort -z -n | tail -1 | cut -d ' ' -f 2)"

        if [[ "$VERBOSE" -eq 1 ]]; then
          echo "Batch of the namesake files found: ${KEEP_NEWEST_FILE_BATCH[*]}..."
          echo "Found the youngest file in batch: $YOUNGEST_FILE..."
        fi

        for F in "${KEEP_NEWEST_FILE_BATCH[@]}"; do
          if [[ "$F" != "$YOUNGEST_FILE" ]]; then
            if [[ "$YES_ANY" -eq 1 ]]; then
              if [[ "$VERBOSE" -eq 1 ]]; then
                echo "Removing older version: $F..."
              fi
              rm -f "$F"
            else
              read -p "Remove older version: $F? (y/n) " ANSWER </dev/tty
              if [[ "$ANSWER" == 'y' ]]; then
                rm -f "$F"
              fi
            fi
          fi
        done
      }
    done
}

do_move () {
    for catalog in "${SOURCE[@]}"; do
        [[ "$catalog" == "$X_DIR" ]] && continue

        find "$catalog" -type f -print0 | while IFS= read -r -d $'\0' file; do
            if [[ "$YES_ANY" -eq 1 ]]; then
                [[ "$VERBOSE" -eq 1 ]] && echo "Doing: $OPTION_NAME $file to $X_DIR..."
                cleared_file=$(echo -n "$file" | tr '/' '-')
                new_filename="$X_DIR/$cleared_file"
                rsync -a --relative "$file" "$new_filename"
            else
                read -p "$OPTION_NAME $file to $X_DIR? (y/n) " answer </dev/tty
                [[ "$answer" = "y" ]] && {
                    cleared_file=$(echo -n "$file" | tr '/' '-')
                    new_filename="$X_DIR/$cleared_file"
                    rsync -a --relative "$file" "$new_filename"
                }
            fi
        done
    done
}

do_rename () {
    for catalog in "${SOURCE[@]}"; do
        find "$catalog" -type f -print0 | while read -d $'\0' FILE; do
            echo "File: $FILE"
            read -p "Rename this file? (y/n) "  ANSWER </dev/tty

            if [[ "$ANSWER" = "y" ]]; then
                read -p "Enter the new filename: " NEW_FILENAME </dev/tty
                mv "$FILE" "$(dirname "$FILE")/$NEW_FILENAME"
                echo "File renamed to: $NEW_FILENAME"
            else
                echo "Skipping file"
            fi
        done
    done
}


do_default_perms() {
    while IFS= read -r -d $'\0' FILE; do
        if [[ ! -w "$FILE" || ! -x "$FILE" || ! -r "$FILE" ]]; then
            if [[ "$YES_ANY" -eq 1 ]]; then
                if [[ "$VERBOSE" -eq 1 ]]; then
                    echo "Altering permissions of $FILE to default ($DEFAULT_PERMISSIONS)..."
                fi
                chmod "$DEFAULT_PERMISSIONS" "$FILE"
            else
                read -p "Change $FILE permissions to default ($DEFAULT_PERMISSIONS)? (y/n) " ANSWER </dev/tty
                if [[ "$ANSWER" == 'y' ]]; then
                    chmod "$DEFAULT_PERMISSIONS" "$FILE"
                fi
            fi
        fi
    done < <(find "${SOURCE[@]}" -type f -print0)
}

do_symbols () {
    while IFS= read -r -d $'\0' FILE; do
        if [[ "$FILE" =~ [$SYMBOLS_TO_SWAP] ]]; then
            # Escape the symbols #, $, \ with backslashes
            ESCAPED_SYMBOLS_TO_SWAP=$(printf '%s' "$SYMBOLS_TO_SWAP" | sed 's/[#\$\\]/\\&/g')
            NEW_FILENAME=$(echo "$FILE" | sed "s/[$ESCAPED_SYMBOLS_TO_SWAP]/$SYMBOL_TO_SWAP_TO/g")
            if [[ "$YES_ANY" -eq 1 ]]; then
                if [[ "$VERBOSE" -eq 1 ]]; then
                    echo "Renaming file: $FILE -> $NEW_FILENAME"
                fi
                mv -f -- "$FILE" "$NEW_FILENAME"
            else
                read -p "Rename file $FILE to $NEW_FILENAME? (y/n) " ANSWER </dev/tty
                if [[ "$ANSWER" == 'y' ]]; then
                    mv -f -- "$FILE" "$NEW_FILENAME"
                fi
            fi
        fi
    done < <(find "${SOURCE[@]}" -type f -print0)
}

if [[ "$VERBOSE" -eq 1 ]]; then
    printstate
fi

for TASK in "${TASK_LIST[@]}"; do
    case "$TASK" in
        RENAME)
            do_rename
            ;;
        MOVE)
            OPTION="mv -f --"
            OPTION_NAME="move"
            do_move
            ;;
        COPY)
            OPTION="cp -r --"
            OPTION_NAME="copy"
            do_move
            ;;
        REMOVE_DUPS)
            do_duplicates
            ;;
        REMOVE_EMPTY)
            do_empty
            ;;
        REMOVE_TMP)
            do_remove_tmp
            ;;
        KEEP_NEWEST)
            do_keep_newest
            ;;
        DEFAULT_PERMS)
            do_default_perms
            ;;
        SWAP_TEXT)
            do_symbols
            ;;

    esac
done
