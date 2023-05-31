


## Author
Mateusz Krakowski

## Help 
```
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
    -s, --swap-text     swap text symbols TEXT_TO_SWAP defined in .file_cleaner_config to the SOMBOL_TO_SWAP_TO
    -v, --verbose       Print detailed information about what the program is doing
    -y, --yes-any       Do not ask for confirmation before executing any action 
    -h, --help          Display this help message
    Note: Options -s and -p require root access
```


## How to run
- Specyfy configuration in .file_cleaner_config
- Run file_cleaner.sh with desired options

## Example usage
use flag -y to skip confirmation process
```
# Do everything
./file_cleaner.sh -x ./testing_dir/X testing_dir/dir1 testing_dir/dir2 -y -d -e -t -n -p -s -m -v
# Move files to X directory and remove empty files and duplicates based on their content
./file_cleaner.sh -x ./testing_dir/X testing_dir/dir1 testing_dir/dir2 -y --move --remove-empty --remove-dups


