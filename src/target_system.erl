%%%-------------------------------------------------------------------
%%% File        : target_system.erl
%%% Author      : Found in http://www.erlang.se/doc/doc-5.5.2/doc/system_principles/part_frame.html
%%% Changes by  : Miguel Rodríguez Rubinos <miguel.rodriguez@nomasystems.com>
%%% Description : Creates a target system for a given application.
%%%               More info in Erlang System Principles Documentation.
%%%
%%% Created : 12 Jan 2007 by Miguel Rodríguez Rubinos <miguel.rodriguez@nomasystems.com>
%%%-------------------------------------------------------------------
-module(target_system).
-include_lib("kernel/include/file.hrl").
-export([create/1, create/4, install/2]).
-define(BUFSIZE, 8192).

%% @spec create(RelFileName) -> Result
%%    RelFileName = string()
%%    Result = ok
%%
%% @doc Creates the target system release for application <tt>RelFileName</tt>.
%%      Notes: 
%%        - RelFileName below is the *stem* without trailing .rel,
%%          .script etc.
%%        - This script is suposed to be used from APP root dir. Outside ebin.
%% @end 
create(RelFileName) ->
    {ok, Cwd} = file:get_cwd(),
    Path = filename:join([Cwd, "ebin"]),
    create(RelFileName, Path, [], []).


%% @spec create(RelFileName, RelPath, SOpts, TOpts) -> Result
%%    RelFileName = string()
%%    RelPath = string()
%%    SOpts = no_module_tests | local | 
%%                 {variables, [Var]} | exref | {exref, [App]} | silent | 
%%                 {outdir,Dir}
%%    TOpts = {dirs,[IncDir]} | {variables,[Var]} | 
%%              {var_tar,VarTar} | {erts,Dir} | no_module_tests | exref | 
%%              {exref,[App]} | silent | {outdir,Dir}
%%    Dir = string()
%%    Var = {VarName,Prefix}
%%    VarName = string()
%%    Prefix = string()
%%    App = atom()
%%    IncDir = src | include | atom()
%%    VarTar = include | ownfile | omit
%%    Machine = atom()
%%    Result = ok
%%
%% @doc Creates the target system release for application <tt>RelFileName</tt>.
%%      More info for Options could be looked up in SASL Reference.
%%      Notes: 
%%         - RelFileName below is the *stem* without trailing .rel,
%%           .script etc.
%%         - Relpath is 
%% @end 
create(RelFileName, RelPath, SOpts, TOpts) ->
    RelFile = filename:join([RelPath, RelFileName])++".rel", 
    ScriptOpts = case lists:keymember(path, 1, SOpts) of
		     true ->
			 SOpts;
		     _ ->
			 [{path, [RelPath]}|SOpts]
		 end,
    TarOpts = case lists:keymember(path, 1, TOpts) of
		     true ->
			 TOpts;
		     _ ->
			 [{path, [RelPath]}|TOpts]
		 end,
    io:fwrite("Reading file: \"~s\" ...~n", [RelFile]),
    {ok, [RelSpec]} = file:consult(RelFile),
    io:fwrite("Creating file: \"~s\" from \"~s\" ...~n", 
              ["plain.rel", RelFile]),
    {release,
     {RelName, RelVsn},
     {erts, ErtsVsn},
     AppVsns} = RelSpec,
    PlainRelSpec = {release, 
                    {RelName, RelVsn},
                    {erts, ErtsVsn},
                    lists:filter(fun({kernel, _}) -> 
                                         true;
                                    ({stdlib, _}) ->
                                         true;
                                    (_) ->
                                         false
                                 end, AppVsns)
                   },
    {ok, Fd} = file:open("plain.rel", [write]),
    io:fwrite(Fd, "~p.~n", [PlainRelSpec]),
    file:close(Fd),

    io:fwrite("Making \"plain.script\" and \"plain.boot\" files ...~n"),
    make_script("plain", []),

    io:fwrite("Making \"~s.script\" and \"~s.boot\" files ...~n", 
              [RelFileName, RelFileName]),
    make_script(RelFileName, ScriptOpts),

    TarFileName = io_lib:fwrite("~s.tar.gz", [RelFileName]),
    io:fwrite("Creating tar file \"~s\" ...~n", [TarFileName]),
    make_tar(RelFileName, TarOpts),

    io:fwrite("Creating directory \"tmp\" ...~n"),
    file:make_dir("tmp"), 

    io:fwrite("Extracting \"~s\" into directory \"tmp\" ...~n", [TarFileName]),
    extract_tar(TarFileName, "tmp"),

    TmpBinDir = filename:join(["tmp", "bin"]),
    ErtsBinDir = filename:join(["tmp", "erts-" ++ ErtsVsn, "bin"]),
    io:fwrite("Deleting \"erl\" and \"start\" in directory \"~s\" ...~n", 
              [ErtsBinDir]),
    file:delete(filename:join([ErtsBinDir, "erl"])),
    file:delete(filename:join([ErtsBinDir, "start"])),

    io:fwrite("Creating temporary directory \"~s\" ...~n", [TmpBinDir]),
    file:make_dir(TmpBinDir),

    io:fwrite("Copying file \"plain.boot\" to \"~s\" ...~n", 
              [filename:join([TmpBinDir, "start.boot"])]),
    copy_file("plain.boot", filename:join([TmpBinDir, "start.boot"])),

    io:fwrite("Copying files \"epmd\", \"run_erl\" and \"to_erl\" from \n"
              "\"~s\" to \"~s\" ...~n", 
              [ErtsBinDir, TmpBinDir]),
    copy_file(filename:join([ErtsBinDir, "epmd"]), 
              filename:join([TmpBinDir, "epmd"]), [preserve]),
    copy_file(filename:join([ErtsBinDir, "run_erl"]), 
              filename:join([TmpBinDir, "run_erl"]), [preserve]),
    copy_file(filename:join([ErtsBinDir, "to_erl"]), 
              filename:join([TmpBinDir, "to_erl"]), [preserve]),

    StartErlDataFile = filename:join(["tmp", "releases", "start_erl.data"]),
    io:fwrite("Creating \"~s\" ...~n", [StartErlDataFile]),
    StartErlData = io_lib:fwrite("~s ~s~n", [ErtsVsn, RelVsn]),
    write_file(StartErlDataFile, StartErlData),
    
    io:fwrite("Recreating tar file \"~s\" from contents in directory "
              "\"tmp\" ...~n", [TarFileName]),
    {ok, Tar} = erl_tar:open(TarFileName, [write, compressed]),
    {ok, Cwd} = file:get_cwd(),
    file:set_cwd("tmp"),
    erl_tar:add(Tar, "bin", []),
    erl_tar:add(Tar, "erts-" ++ ErtsVsn, []),
    erl_tar:add(Tar, "releases", []),
    erl_tar:add(Tar, "lib", []),
    erl_tar:close(Tar),
    file:set_cwd(Cwd),
    io:fwrite("Removing directory \"tmp\" ...~n"),
    remove_dir_tree("tmp"),
    %%TODO: This can be improved!!!
    io:fwrite("Removing generated files, i.e. plain.*...~n"),
    os:cmd("rm -rfv plain.* "++ RelFileName++".boot "++ RelFileName++".script"),
    ok.

install(RelFileName, RootDir) ->
    TarFile = RelFileName ++ ".tar.gz", 
    io:fwrite("Extracting ~s ...~n", [TarFile]),
    extract_tar(TarFile, RootDir),
    StartErlDataFile = filename:join([RootDir, "releases", "start_erl.data"]),
    {ok, StartErlData} = read_txt_file(StartErlDataFile),
    [ErlVsn, _RelVsn| _] = string:tokens(StartErlData, " \n"),
    ErtsBinDir = filename:join([RootDir, "erts-" ++ ErlVsn, "bin"]),
    BinDir = filename:join([RootDir, "bin"]),
    io:fwrite("Substituting in erl.src, start.src and start_erl.src to\n"
              "form erl, start and start_erl ...\n"),
    subst_src_scripts(["erl", "start", "start_erl"], ErtsBinDir, BinDir, 
                      [{"FINAL_ROOTDIR", RootDir}, {"EMU", "beam"}],
                      [preserve]),
    io:fwrite("Creating the RELEASES file ...\n"),
    create_RELEASES(RootDir, 
                    filename:join([RootDir, "releases", RelFileName])).

%% LOCALS 

%% make_script(RelFileName, SOpts)
%%
make_script(RelFileName, SOpts) ->
    Opts = [no_module_tests|SOpts],
    systools:make_script(RelFileName, Opts).

%% make_tar(RelFileName, TOpts)
%%
make_tar(RelFileName, TOpts) ->
    RootDir = code:root_dir(),
    Opts = [{erts, RootDir}|TOpts],
    systools:make_tar(RelFileName, Opts).

%% extract_tar(TarFile, DestDir)
%%
extract_tar(TarFile, DestDir) ->
    erl_tar:extract(TarFile, [{cwd, DestDir}, compressed]).

create_RELEASES(DestDir, RelFileName) ->
    release_handler:create_RELEASES(DestDir, RelFileName ++ ".rel").

subst_src_scripts(Scripts, SrcDir, DestDir, Vars, Opts) -> 
    lists:foreach(fun(Script) ->
                          subst_src_script(Script, SrcDir, DestDir, 
                                           Vars, Opts)
                  end, Scripts).

subst_src_script(Script, SrcDir, DestDir, Vars, Opts) -> 
    subst_file(filename:join([SrcDir, Script ++ ".src"]),
               filename:join([DestDir, Script]),
               Vars, Opts).

subst_file(Src, Dest, Vars, Opts) ->
    {ok, Conts} = read_txt_file(Src),
    NConts = subst(Conts, Vars),
    write_file(Dest, NConts),
    case lists:member(preserve, Opts) of
        true ->
            {ok, FileInfo} = file:read_file_info(Src),
            file:write_file_info(Dest, FileInfo);
        false ->
            ok
    end.

%% subst(Str, Vars)
%% Vars = [{Var, Val}]
%% Var = Val = string()
%% Substitute all occurrences of %Var% for Val in Str, using the list
%% of variables in Vars.
%%
subst(Str, Vars) ->
    subst(Str, Vars, []).

subst([$%, C| Rest], Vars, Result) when $A =< C, C =< $Z ->
    subst_var([C| Rest], Vars, Result, []);
subst([$%, C| Rest], Vars, Result) when $a =< C, C =< $z ->
    subst_var([C| Rest], Vars, Result, []);
subst([$%, C| Rest], Vars, Result) when  C == $_ ->
    subst_var([C| Rest], Vars, Result, []);
subst([C| Rest], Vars, Result) ->
    subst(Rest, Vars, [C| Result]);
subst([], _Vars, Result) ->
    lists:reverse(Result).

subst_var([$%| Rest], Vars, Result, VarAcc) ->
    Key = lists:reverse(VarAcc),
    case lists:keysearch(Key, 1, Vars) of
        {value, {Key, Value}} ->
            subst(Rest, Vars, lists:reverse(Value, Result));
        false ->
            subst(Rest, Vars, [$%| VarAcc ++ [$%| Result]])
    end;
subst_var([C| Rest], Vars, Result, VarAcc) ->
    subst_var(Rest, Vars, Result, [C| VarAcc]);
subst_var([], Vars, Result, VarAcc) ->
    subst([], Vars, [VarAcc ++ [$%| Result]]).

copy_file(Src, Dest) ->
    copy_file(Src, Dest, []).

copy_file(Src, Dest, Opts) ->
    {ok, InFd} = file:open(Src, {binary, read, raw}),
    {ok, OutFd} = file:open(Dest, {binary, write, raw}),
    do_copy_file(InFd, OutFd),
    file:close(InFd),
    file:close(OutFd),
    case lists:member(preserve, Opts) of
        true ->
            {ok, FileInfo} = file:read_file_info(Src),
            file:write_file_info(Dest, FileInfo);
        false ->
            ok
    end.

do_copy_file(InFd, OutFd) ->
    case file:read(InFd, ?BUFSIZE) of
        {ok, Bin} ->
            file:write(OutFd, Bin),
            do_copy_file(InFd, OutFd);
        eof  ->
            ok
    end.
       
write_file(FName, Conts) ->
    {ok, Fd} = file:open(FName, [write]),
    file:write(Fd, Conts),
    file:close(Fd).

read_txt_file(File) ->
    {ok, Bin} = file:read_file(File),
    {ok, binary_to_list(Bin)}.

remove_dir_tree(Dir) ->
    remove_all_files(".", [Dir]).

remove_all_files(Dir, Files) ->
    lists:foreach(fun(File) ->
                          FilePath = filename:join([Dir, File]),
                          {ok, FileInfo} = file:read_file_info(FilePath),
                          case FileInfo#file_info.type of
                              directory ->
                                  {ok, DirFiles} = file:list_dir(FilePath), 
                                  remove_all_files(FilePath, DirFiles),
                                  file:del_dir(FilePath);
                              _ ->
                                  file:delete(FilePath)
                          end
                  end, Files).
