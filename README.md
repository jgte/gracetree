# gracetree


Tool to list and retrieve data from files with structured names inside a directory tree.

    Usage: gracetree.rb -x COMMAND [options]

    -p, --parameters-file PARFILE    File with parameters (default /home1/00767/byaa676/data/gracetree/default.par).
    -x, --execute COMMAND            Perform one (or more, using the COMMAND1+COMMAND2+...COMMANDN notation) of the following operations (default is <ls>):
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
    -r, --root ROOT                  Index files below ROOT(default is </corral-tacc/utexas/csr>).
    -S, --sink SINK                  Copy files to SINK/FILETYPE (default is </scratch/00767/byaa676/gracetree>).
    -y, --year YEAR                  Replace the placeholder 'YEAR' in SUBIR or INFIX with this value (default is <[0-9][0-9]>).
    -m, --month MONTH                Replace the placeholder 'MONTH' in SUBIR or INFIX with this value (default is <[0-9][0-9]>).
    -d, --day DAY                    Replace the placeholder 'DAY' in SUBIR or INFIX with this value (default is <[0-9][0-9]>).
    -j, --jobid JOBID                Replace the placeholder 'JOBID' in PREFIX, INFIX or SUFFIX with this value (default is <*>).
    -t, --filetype FILETYPE          Gather files of type FILETYPE (no default value set; add 'filetype: <default value>' to the parameter file).
    -g, --pattern PATTERN            Grep PATTERN from the files in SINK/FILETYPE (no default value set; add 'pattern: <default value>' to the parameter file).
    -D, --data DATA                  With '-x list2file', save results to DATA directory (default is </home1/00767/byaa676/data/gracetree>).
    -a, --arc ARC                    Replace the placeholder 'ARC' in INFIX with this value (default is <*>).
    -s, --satellite SAT              Replace the placeholder 'SAT' in PREFIX, INFIX or SUFFIX with this value (default is <[AB]>).
    -c, --[no-]clean-grep            Remove filename and PATTERN from grep output (default is <false>).
    -?, --[no-]debug                 Turn on debug mode (very verbose!) (default is <false>).
    -h, --help                       Display this screen.
