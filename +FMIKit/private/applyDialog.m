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
              
    % custom sources
    custom_include = get_param(gcs, 'CustomInclude');
    custom_include = split_paths(custom_include);
    for i = 1:numel(custom_include)
        mex_args{end+1} = ['-I"' custom_include{i} '"'];
    end
    
    % custom libraries
    custom_library = get_param(gcs, 'CustomLibrary');
    custom_library = split_paths(custom_library);
    for i = 1:numel(custom_library)
        mex_args{end+1} = ['"' custom_library{i} '"'];
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
