# gracetree

Tool to list and retrieve data from files with structured names inside a directory tree.

    Usage: gracetree.rb -x COMMAND [options]

    -p, --parameters-file PARFILE    File with parameters (default /home1/00767/byaa676/cloud/Common/github/gracetree/default.par, i.e. in the same directory as gracetree.rb)
    -x, --execute COMMAND            Perform one (or more, using the COMMAND1+COMMAND2+...COMMANDN notation) of the following operations (default is 'ls'):
    arc
    awk
    awkstr
    copy
    day
    debug
    debug_common_args
    debugall
    debugparticles
    filename
    filename_quick
    filename_raw
    filetype
    filetypelist
    find
    findstr
    grep
    grepstr
    jobid
    jobid_replaced
    ls
    lsstr
    month
    parfile
    particles
    print
    released_solution
    sat
    sink
    year
    -r, --root ROOT                  Index files below ROOT (default is '/corral-tacc/utexas/csr').
    -S, --sink SINK                  Copy files to SINK/FILETYPE (default is '/scratch/00767/byaa676/gracetree', i.e. $SCRATCH/gracetree).
    -y, --year YEAR                  Replace the placeholder 'YEAR' in SUBIR or INFIX with this value (default is '[0-9][0-9]').
    -m, --month MONTH                Replace the placeholder 'MONTH' in SUBIR or INFIX with this value (default is '[0-9][0-9]').
    -d, --day DAY                    Replace the placeholder 'DAY' in SUBIR or INFIX with this value (default is '[0-9][0-9]').
    -j, --jobid JOBID                Replace the placeholder 'JOBID' in PREFIX, INFIX or SUFFIX with this value (default is '*').
    -t, --filetype FILETYPE          Gather files of type FILETYPE (no default value set; add 'filetype: default_value' to the parameter file).
    -g, --pattern PATTERN            Grep PATTERN from the files in SINK/FILETYPE (no default value set; add 'pattern: default_value' to the parameter file).
    -a, --arc ARC                    Replace the placeholder 'ARC' in INFIX with this value (default is '*').
    -s, --satellite SAT              Replace the placeholder 'SAT' in PREFIX, INFIX or SUFFIX with this value (default is '[AB]').
    -c, --[no-]clean-grep            Remove filename and PATTERN from grep output (default is 'false').
    -?, --[no-]debug                 Turn on debug mode (default is 'false' and makes output very verbose!).
    -h, --help                       Display this screen.

## Instalation

There are a few possibilities to use this software:

### Clone this repository

Simply execute the following command:

    git clone https://github.com/jgte/gracetree.git
    
A directory `gracetree` should appear in the current directory. Add it to your `$PATH`, or call the `gracetree.rb` with the complete path name. 

This installtion method is preferred, since you'll end up with your own copy of the code and be able to selectively incorporate any future changes (with `git pull`). You'll also get your own `default.par` parameter file, which you can change to suit your needs. Any improvement in the code is most welcome, so please become a collaborator or fork this repository.

### Use my copy in Lonestar 5

If you work on Lonestart 5, you can use the `gracetree.rb` script in the following directory:

    /home1/00767/byaa676/bin
    
Copy `gracetree.rb` (along with `default.par`) to a directory of your choice (ideally one that is in your `$PATH`) or add the directory above to your `$PATH` (be aware there are numerous other scripts in this directory, and some may not work for you). 

You can also link the `gracetree.rb` and `default.par` (symbolically, i.e. `ln -s`) in the directory above to a location of your choice. This is the least preferred method, since any change I make to either file will reflect on you.

The `gracetree.rb` utility does not work without the parameter file, unless if the `-p` option is used, along with an alternative parameter file.

## Operations

Refer to the slides in `gracetree-presentation.pdf` for some examples on using this tool.

## Problems?

Should you encounter a problem, please [let me know](https://directory.utexas.edu/index.php?q=joao+encarnacao)!

