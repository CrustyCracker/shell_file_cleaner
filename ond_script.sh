#!/bin/bash

X_DIR="./X"
SOURCE=()
TASK_LIST=()        # Task list used to have all hyperparameters set before executing
FASTFORWARD=0       # for default, fast-forward option is not set
VERBOSE=0           # for default, verbouse option is not set

source ./.clean_files     # DEFAULT_ACCESS; UNWANTED_SYMBOLS; UNWANTED_SYMBOLS_SUBSTITUTE; TMP_FILES

printstate () {
    echo X_DIR = $X_DIR
    echo SOURCE = ${SOURCE[@]}
    echo TASK_LIST = ${TASK_LIST[@]}
    echo FASTFORWARD = $FASTFORWARD
}


exe_help () {
    cat << EOF
Usage: projekt.sh [OPTION]... DIRECTORIES...
    -h  --help          Display help message
    -x  --set_dir       Specify target directory X
    -m  --move          Move files to directory X
    -c  --copy          Copy files to directory X
    -d  --duplicates    Remove duplicates (in terms of content)
    -e  --empty         Remove empty files
    -t  --temporary     Remove temporary files
    -n  --namesake      Preserve the newest of namesake files
    -p  --permissions   Set permissions to default
    -s  --symbols       Substitute problematic symbols with pre-chosen ('.')
    -r  --rename        Enable hot-plugged all touched files renaming
    -f  --fastforward   Do not interact with caller: use default choices
    -v  --verbose       Print state messages

    Be concious options -symbols & -permissions may require you to be root
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
        -m | --move)
            TASK_LIST+=("MOVE")
            shift
            ;;
        -c | --copy)
            TASK_LIST+=("COPY")
            shift
            ;;
        -d | --duplicates)
            TASK_LIST+=("DUPLICATES")
            shift
            ;;
        -e | --empty)
            TASK_LIST+=("EMPTY")
            shift
            ;;
        -t | --temporary)
            TASK_LIST+=("TEMPORARY")
            shift
            ;;
        -n | --namesake)
            TASK_LIST+=("NAMESAKE")
            shift
            ;;
        -p | --permissions)
            TASK_LIST+=("PERMISSIONS")
            shift
            ;;
        -s | --symbols)
            TASK_LIST+=("SYMBOLS")
            shift
            ;;
        -r | --rename)
            TASK_LIST+=("RENAME")
            shift
            ;;
        -f | --fastforward)
            FASTFORWARD=1
            shift
            ;;
        -v | --verbose)
            VERBOSE=1
            shift
            ;;
        -*)
            echo "Invalid option $1" 1>&2   # print error on cerr
            exe_help
            ;;
        *)
            SOURCE+=("$1")
            shift;
            ;;
    esac
done

do_move () {
    for CATALOG in "${SOURCE[@]}"; do
        if [[ "$CATALOG" == "$X_DIR" ]]; then
            continue
        fi

        find "$CATALOG" -type f -print0 | {
            while IFS= read -r -d $'\0' FILE; do

                if [[ "$FASTFORWARD" -eq 1 ]]; then # fastforward is set
                    if [[ "$VERBOSE" -eq 1 ]]; then
                        echo Doing: $OPTION_NAME $FILE to $X_DIR...
                    fi
                    CLEARED_FILE=$(echo -n "$FILE" | sed -r 's/\//-/g') # replace / with -
                    NEW_FILENAME=$(echo -n "$X_DIR/$CLEARED_FILE") # concatenate
                    $OPTION "$FILE" "$NEW_FILENAME"
                else
                    read -p "Do you want to $OPTION_NAME $FILE to $X_DIR? (y/n) " ANSWER </dev/tty
                    if [[ "$ANSWER" = "y" ]]; then
                        CLEARED_FILE=$(echo -n "$FILE" | sed -r 's/\//-/g') # replace / with -
                        NEW_FILENAME=$(echo -n "$X_DIR/$CLEARED_FILE") # concatenate
                        $OPTION "$FILE" "$NEW_FILENAME"
                    fi
                fi
            done
        }
    done
}

do_rename () {
    find "${SOURCE[@]}" -type f -print0 | {
        while IFS= read -r -d $'\0' FILE; do
            read -p "Do you want to rename file: $FILE? (y/n) "  ANSWER </dev/tty

            if [[ "$ANSWER" = "y" ]]; then
                read -p "Provide new name: " NEW_FILENAME </dev/tty
                mv "$FILE" "$NEW_FILENAME"
            fi
        done
    }
}

DUPLICATED_FILES_BATCH=()
OLDEST_FILE=""
OLDEST_FILE_TIME=""

find_oldest() {
    OLDEST_FILE="$DUPLICATED_FILES_BATCH"
    OLDEST_FILE_TIME=$( stat -c %Y "$OLDEST_FILE" )

    for F in "${DUPLICATED_FILES_BATCH[@]}"; do
        if [[ $( stat -c %Y "$F" ) -lt $OLDEST_FILE_TIME ]]; then
            OLDEST_FILE=$F
            OLDEST_FILE_TIME=$( stat -c %Y "$F" )
        fi
    done
}

exe_duplicates() {
    if [[ $CURRENT_HASH == "" ]]; then
        return
    fi

    OLDEST_COMMAND="-gt"
    if [[ "$VERBOSE" -eq 1 ]]; then
        echo Batch of the same files found: "${DUPLICATED_FILES_BATCH[@]}..."
        find_oldest
        echo Found the oldest file in batch: $OLDEST_FILE...
    else
        find_oldest
    fi

    if [[ "$FASTFORWARD" -eq 1 ]]; then
        for F in "${DUPLICATED_FILES_BATCH[@]}"; do
            if [[ "$F" != "$OLDEST_FILE" ]]; then
                if [[ "$VERBOSE" -eq 1 ]]; then
                    echo "Removing duplicate: $F..."
                fi
                rm -f "$F"
            fi
        done
    else
        for F in "${DUPLICATED_FILES_BATCH[@]}"; do
            if [[ "$F" != "$OLDEST_FILE" ]]; then
                read -p "Do you want to remove duplicate: $FILE? (y/n) " ANSWER </dev/tty
                if [[ "$ANSWER" == 'y' ]]; then
                    rm -f "$F"
                fi
            fi
        done
    fi
}

do_duplicates () {
    # https://unix.stackexchange.com/questions/277697/whats-the-quickest-way-to-find-duplicated-files
    find "${SOURCE[@]}" ! -empty -type f -exec md5sum {} + | sort | uniq -w32 -dD | {
        CURRENT_HASH=""

        while IFS= read -r -d $'\n' LINE; do

            HASH=$(echo "$LINE" | cut -c 1-32)
            FILE=$(echo "$LINE" | cut -c 35-)

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

do_empty () {
    find "${SOURCE[@]}" -type f -size 0 -print0  | {
        while IFS= read -r -d $'\0' FILE; do

            if [[ "$FASTFORWARD" -eq 1 ]]; then
                if [[ "$VERBOSE" -eq 1 ]]; then
                    echo "Removing empty file: $FILE..."
                fi
                rm -f "$FILE"
            else
                read -p "Do you want to remove empty file: $FILE? (y/n) " ANSWER </dev/tty

                if [[ "$ANSWER" = "y" ]]; then
                    rm -f "$FILE"
                fi
            fi
        done
    }
}

do_temporary () {
    find "${SOURCE[@]}" -type f -regex "$TMP_FILES" -print0 | {
        while IFS= read -r -d $'\0' FILE; do

            if [[ $FASTFORWARD -eq 1 ]]; then
                if [[ $VERBOSE -eq 1 ]]; then
                    echo Removing temporary file "$FILE"...
                fi
                rm -f "$FILE"
            else
                read -p "Do you want to remove temporary file: $FILE? (y/n) " ANSWER </dev/tty
                if [[ "$ANSWER" = "y" ]]; then
                    rm -f "$FILE"
                fi
            fi
        done
    }
}

do_namesake () {
    find "${SOURCE[@]}" -type f -print0 | sed 's_.*/__' -z | sort -z |  uniq -z -d | {
        while IFS= read -r -d $'\0' NAMESAKE; do
            find "${SOURCE[@]}" -name "$NAMESAKE" -print0 | {
                NAMESAKE_FILE_BATCH=()
                while IFS= read -r -d $'\0' FILE; do
                    NAMESAKE_FILE_BATCH+=("$FILE")
                done

                if [[ "$VERBOSE" -eq 1 ]]; then
                    echo Batch of the namesake files found: "${NAMESAKE_FILE_BATCH[@]}..."
                fi

                YOUNGEST_FILE="$NAMESAKE_FILE_BATCH"
                YOUNGEST_FILE_TIME=$( stat -c %Y "$YOUNGEST_FILE" )

                for F in "${NAMESAKE_FILE_BATCH[@]}"; do
                    if [[ $( stat -c %Y "$F" ) -gt $YOUNGEST_FILE_TIME ]]; then
                        YOUNGEST_FILE=$F
                        YOUNGEST_FILE_TIME=$( stat -c %Y "$F" )
                    fi
                done

                if [[ "$VERBOSE" -eq 1 ]]; then
                    echo Found the youngest file in batch: $YOUNGEST_FILE...
                fi

                if [[ "$FASTFORWARD" -eq 1 ]]; then
                    for F in "${NAMESAKE_FILE_BATCH[@]}"; do
                        if [[ "$F" != "$YOUNGEST_FILE" ]]; then
                            if [[ "$VERBOSE" -eq 1 ]]; then
                                echo "Removing older version: $F..."
                            fi
                            rm -f "$F"
                        fi
                    done
                else
                    for F in "${NAMESAKE_FILE_BATCH[@]}"; do
                        if [[ "$F" != "$YOUNGEST_FILE" ]]; then
                            read -p "Do you want to remove older version: $F? (y/n) " ANSWER </dev/tty
                            if [[ "$ANSWER" == 'y' ]]; then
                                rm -f "$F"
                            fi
                        fi
                    done
                fi
            }
        done
    }
}

do_permissions () {
    find "${SOURCE[@]}" -type f -not -perm "$DEFAULT_ACCESS" -print0 | {
        while IFS= read -r -d $'\0' FILE; do

            if [[ "$FASTFORWARD" -eq 1 ]]; then
                if [[ "$VERBOSE" -eq 1 ]]; then
                    echo "Altering permissions of $FILE from $(stat -c "%a" $FILE) to $DEFAULT_ACCESS..."
                fi
                chmod a-rwx $FILE
                chmod +$DEFAULT_ACCESS $FILE
            else
                read -p "Do you want to change $FILE permissions from $(stat -c "%a" $FILE) to default ($DEFAULT_ACCESS)? (y/n) " ANSWER </dev/tty
                if [[ "$ANSWER" == 'y' ]]; then
                    chmod a-rwx $FILE
                    chmod +$DEFAULT_ACCESS $FILE
                fi
            fi
        done
    }
}

do_symbols () {
    find "${SOURCE[@]}" -type f -print0 | grep -e "[${UNWANTED_SYMBOLS}]" -z | {
        while IFS= read -r -d $'\0' FILE; do
            NEW_FILENAME=$(echo "$FILE" | sed "s/[${UNWANTED_SYMBOLS}]/${UNWANTED_SYMBOLS_SUBSTITUTE}/g")
            if [[ "$FASTFORWARD" -eq 1 ]]; then
                if [[ "$VERBOSE" -eq 1 ]]; then
                    echo Changing undesirable file name: $FILE into $NEW_FILENAME...
                fi
                mv -f -- "$FILE" "$NEW_FILENAME"
            else
                read -p "Do you want to change $FILE name to more conveniant $NEW_FILENAME? (y/n) " ANSWER </dev/tty
                if [[ "$ANSWER" == 'y' ]]; then
                    mv -f -- "$FILE" "$NEW_FILENAME"
                fi
            fi
        done
    }
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
        DUPLICATES)
            do_duplicates
            ;;
        EMPTY)
            do_empty
            ;;
        TEMPORARY)
            do_temporary
            ;;
        NAMESAKE)
            do_namesake
            ;;
        PERMISSIONS)
            do_permissions
            ;;
        SYMBOLS)
            do_symbols
            ;;

    esac
done
