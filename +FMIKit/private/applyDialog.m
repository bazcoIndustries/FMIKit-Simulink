function applyDialog(dialog)

%#ok<*AGROW>

% set the user data
userData = userDataToStruct(dialog.getUserData());
set_param(dialog.blockHandle, 'UserData', userData, 'UserDataPersistent', 'on');

% set the S-function parameters
FMIKit.setSFunctionParameters(dialog.blockHandle)

if userData.useSourceCode

    % generate the S-function source
    dialog.generateSourceSFunction();

    model_identifier = char(dialog.getModelIdentifier());
    unzipdir = char(dialog.getUnzipDirectory());

    % build the S-function
    clear(['sfun_' model_identifier])

    disp(['Compiling S-function ' model_identifier])
    
    mex_args = {};
              
    % include directories
    include_dirs = get_param(gcs, 'SimUserIncludeDirs');
    include_dirs = split_paths(include_dirs);
    for i = 1:numel(include_dirs)
        mex_args{end+1} = ['-I"' include_dirs{i} '"'];
    end
    
    % libraries
    libraries = get_param(gcs, 'SimUserLibraries');
    libraries = split_paths(libraries);
    for i = 1:numel(libraries)
        mex_args{end+1} = ['"' libraries{i} '"'];
    end
    
    % S-function source
    mex_args{end+1} = ['sfun_' model_identifier '.c'];

    % FMU sources
    it = dialog.getSourceFiles().listIterator();

    while it.hasNext()
        mex_args{end+1} = ['"' fullfile(unzipdir, 'sources', it.next()) '"'];
    end

    try
        mex(mex_args{:})
    catch e
        disp('Failed to compile S-function')
        disp(e.message)
        % rethrow(e)
    end

end

end


function l = split_paths(s)
% split a list of space separated and optionally quoted paths into
% a cell array of strings 

s = [s ' ']; % append a space to catch the last path

l = {};  % path list

p = '';     % path
q = false;  % quoted path

for i = 1:numel(s)
  
    c = s(i); % current character
  
    if q
        if c == '"'
            q = false;
            if ~isempty(p)
                l{end+1} = p;
            end
            p = '';
        else
            p(end+1) = c;
        end
        continue
    end
      
    if c == '"'
        q = true;
    elseif c == ' '
        if ~isempty(p)
            l{end+1} = p;
        end
        p = '';
    else
        p(end+1) = c;
    end
end

end
