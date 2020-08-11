function grtfmi_make_rtw_hook(hookMethod, modelName, rtwRoot, templateMakefile, buildOpts, buildArgs, buildInfo)

switch hookMethod

    case 'after_make'

        current_dir = pwd;
        
        % remove FMU build directory from previous build
        if exist('./FMUArchive', 'dir')
            rmdir('./FMUArchive', 's');
        end
        
        % create the archive directory (uncompressed FMU)
        mkdir('./FMUArchive');
        
        template_dir = get_param(gcs, 'FMUTemplateDir');
        
        % copy template files
        if ~isempty(template_dir)
            copyfile(template_dir, 'FMUArchive');
        end
        
        % remove fmiwrapper.inc for referenced models
        if ~strcmp(current_dir(end-11:end), '_grt_fmi_rtw')
            delete('fmiwrapper.inc');
            return
        end

        if strcmp(get_param(gcs, 'GenCodeOnly'), 'on')
            return
        end

        pathstr = which('grtfmi.tlc');
        [grtfmi_dir, ~, ~] = fileparts(pathstr);
        
        % add model.png
        if strcmp(get_param(gcs, 'AddModelImage'), 'on')
            % create an image of the model
            print(['-s' modelName], '-dpng', fullfile('FMUArchive', 'model.png'));
        else
            % use the generic Simulink logo
            copyfile(fullfile(grtfmi_dir, 'model.png'), fullfile('FMUArchive', 'model.png'));
        end
        
        command = get_param(modelName, 'CMakeCommand');
        command = grtfmi_find_cmake(command);
        generator = get_param(modelName, 'CMakeGenerator');
        source_code_fmu = get_param(modelName, 'SourceCodeFMU');
        fmi_version = get_param(modelName, 'FMIVersion');
        
        % copy extracted nested FMUs
        nested_fmus = find_system(modelName, 'ReferenceBlock', 'FMIKit_blocks/FMU');
        
        if ~isempty(nested_fmus)
            disp('### Copy nested FMUs')
            for i = 1:numel(nested_fmus)
                nested_fmu = nested_fmus{i};
                unzipdir = FMIKit.getUnzipDirectory(nested_fmu);
                user_data = get_param(nested_fmu, 'UserData');
                dialog = FMIKit.showBlockDialog(nested_fmu, false);
                if user_data.runAsKind == 0
                    model_identifier = char(dialog.modelDescription.modelExchange.modelIdentifier);
                else
                    model_identifier = char(dialog.modelDescription.coSimulation.modelIdentifier);
                end
                disp(['Copying ' unzipdir ' to resources'])                
                copyfile(unzipdir, fullfile('FMUArchive', 'resources', model_identifier), 'f');
            end
        end
        
        disp('### Running CMake generator')
        
        % get model sources
        %[custom_include, custom_source, custom_library] = ...
        %    grtfmi_model_sources(modelName, pwd);
        
        % Get all source files from buildInfo.  Some file names may be relative paths or
        % may not have any path component.  Use Java to detect absolute paths and leave
        % those alone.  (No MATLAB built-in to ascertain absolute or relative paths.)
        % For relative paths, brute-force search the source path list until each file
        % is located.  Warn of any that cannot be found.
        custom_source = buildInfo.getSourceFiles(true, true);
        custom_source_paths = buildInfo.getSourcePaths(true);
       	for k = 1 : length(custom_source)
            f = java.io.File(custom_source{k});
            if ~f.isAbsolute()
                found = false;
                for j = 1 : length(custom_source_paths)
                    proposed = [custom_source_paths{j} '/' custom_source{k}];
                    if exist(proposed, 'file')
                        custom_source{k} = proposed;
                        found = true;
                        break;
                    end
                end
                if ~found
                    warning('*** WARNING: Could not locate %s', custom_source{k});
                end
            end
        end
        
        % remove files from Matlab installation. TODO: these should not be
        % added in the first place but we would have to modify the grt.tlc
        % file to fix this (probably)
        matches = cellfun('isempty', regexp(custom_source, '[\\/](rt_printf\.c|rt_main\.c|rt_malloc_main\.c)$'));
        custom_source = custom_source(matches); 

        custom_include = buildInfo.getIncludePaths(true);

        custom_library_directories = buildInfo.getLibraryPaths(true, true);
        if ~isempty(buildInfo.getLinkObjects)
            custom_library = {buildInfo.getLinkObjects.Name}';
        else
            custom_library = {};
        end
 
        custom_include = cmake_list(custom_include);
        custom_source  = cmake_list(custom_source);
        custom_library = cmake_list(custom_library);
        
        % check for Simscape blocks
        if isempty(find_system(modelName, 'BlockType', 'SimscapeBlock'))
            simscape_blocks = 'off';
        else
            simscape_blocks = 'on';
        end
        
        % write the CMakeCache.txt file
        fid = fopen('CMakeCache.txt', 'w');
        fprintf(fid, 'MODEL:STRING=%s\n', modelName);
        fprintf(fid, 'RTW_DIR:STRING=%s\n', strrep(pwd, '\', '/'));
        fprintf(fid, 'MATLAB_ROOT:STRING=%s\n', strrep(matlabroot, '\', '/'));
        fprintf(fid, 'CUSTOM_INCLUDE:STRING=%s\n', custom_include);
        fprintf(fid, 'CUSTOM_SOURCE:STRING=%s\n', custom_source);
        fprintf(fid, 'CUSTOM_LIBRARY:STRING=%s\n', custom_library);
        fprintf(fid, 'SOURCE_CODE_FMU:BOOL=%s\n', upper(source_code_fmu));
        fprintf(fid, 'SIMSCAPE:BOOL=%s\n', upper(simscape_blocks));
        fprintf(fid, 'FMI_VERSION:STRING=%s\n', fmi_version);
        fprintf(fid, 'COMPILER_OPTIMIZATION_LEVEL:STRING=%s\n', get_param(bdroot, 'CMakeCompilerOptimizationLevel'));
        fprintf(fid, 'COMPILER_OPTIMIZATION_FLAGS:STRING=%s\n', get_param(bdroot, 'CMakeCompilerOptimizationFlags'));
        fclose(fid);
        
        disp('### Generating project')
        status = system(['"' command '" -G "' generator '" "' strrep(grtfmi_dir, '\', '/') '"']);
        assert(status == 0, 'Failed to run CMake generator');

        disp('### Building FMU')
        status = system(['"' command '" --build . --config Release']);
        assert(status == 0, 'Failed to build FMU');

        % copy the FMU to the working directory
        copyfile([modelName '.fmu'], '..');
end

end

function joined = cmake_list(array)
joined = strjoin(array, ';');
joined = strrep(joined, '\', '/');
end
