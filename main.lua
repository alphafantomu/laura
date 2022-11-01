
local system_os, system_arch = jit.os, jit.arch;

local format = string.format;
local os_execute = os.execute;

local uv = require('uv');
local path = require('path');
local extension = require('discordia-extensions');
local bin_package = require('./package');

local cwd = uv.cwd();
local stdin = uv.new_tty(0, true); ---@diagnostic disable-line
local stdout = uv.new_tty(1, false); ---@diagnostic disable-line
local stderr = uv.new_tty(2, false); ---@diagnostic disable-line

local MAX_PERMS = tonumber(777, 8); ---@diagnostic disable-line
local BUILD_NAME = 'build';
local LIBRARY_EXT = '.dll';
local VERSION_FORMAT = 'Laura version: %s';
local REPO_FORMAT = 'GitHub Open Source Repository <%s>';
local SPLIT_FORMAT = '\n======= %s =======';
local COPY_FORMAT = 'copy /v /y "%s" "%s"';
local COPY_FUSED_FORMAT = 'copy /b /y "%s"+"%s" "%s"';
local LOVE2D = path.join('C:', 'Program Files', 'LOVE');
local LOVE2D_EXE = path.join(LOVE2D, 'love.exe');
local ZIP_COMMANDLINE = path.join('C:', 'Program Files', '7-Zip', '7z.exe');

local LOVE2D_FILES = {'license.txt', 'SDL2.dll', 'OpenAL32.dll', 'love.dll', 'lua51.dll', 'mpg123.dll', 'msvcp120.dll', 'msvcr120.dll'};

local fsExists = function(check_path, target_type, msg)
	local data = uv.fs_stat(check_path);
	return assert(data and data.type == target_type, msg);
end;

local qexecute = function(command)
	local res, _, code = os_execute(command);
	assert(res and code == 0, 'execute command encountered an error');
	return res, _, code;
end;

local scanDirectory; scanDirectory = function(dir, callback)
	local handle = assert(uv.fs_scandir(dir));
	local name, t;
	repeat
		name, t = uv.fs_scandir_next(handle);
		if (t == 'file') then
			callback(dir, name);
		elseif (t == 'directory' and name ~= BUILD_NAME) then
			scanDirectory(path.join(dir, name), callback);
		end;
	until not name;
end;

local prepare = function()
	-- Check for 7 Zip --
	if (system_os == 'Windows') then
		local zipper = uv.fs_stat(ZIP_COMMANDLINE);
		assert(zipper and zipper.type == 'file', 'Only 7-Zip is supported to build the project on Windows');
	end;
	-- Make a build folder --
	local data = uv.fs_stat(BUILD_NAME);
	if ((not data) or (data and data.type ~= 'directory')) then
		assert(uv.fs_mkdir(BUILD_NAME, MAX_PERMS));
	end;
end;

local clear = function()
	local data = uv.fs_stat(BUILD_NAME);
	if (data and data.type ~= 'directory') then
		assert(uv.fs_rmdir(BUILD_NAME))
	end;
end;

local createLoveArchive = function()
	local thread = coroutine.running();
	local handle;
	local filename = path.basename(cwd)..'.love';
	local archive_location = path.join(BUILD_NAME, filename);
	if (system_os == 'Windows') then
		handle = assert(uv.spawn(ZIP_COMMANDLINE, {
			cwd = cwd;
			args = {'a', '-tzip', archive_location, '-x!tests', '-x!build', '-x!.vscode', '-x!cdeps', '-xr!*.dll'};
			stdio = {stdin, stdout, stderr};
		}, function(code)
			assert(code == 0, '7-Zip returned '..tostring(code)..' exit code');
			fsExists(archive_location, 'file', 'failed to find file ('..filename..') after 7-Zip archiving');
			handle:close();
			coroutine.resume(thread);
		end));
	end;
	print('Creating love archive...');
	coroutine.yield();
	print('Created '..archive_location);
	return archive_location;
end;

local createExecutable = function(archive)
	local filename = path.basename(archive):sub(1, -6)..'.exe';
	local executable_location = path.join(BUILD_NAME, filename);
	if (system_os == 'Windows') then
		print('Created fused executable...');
		local c_res, _, c_code = qexecute(format(COPY_FUSED_FORMAT, LOVE2D_EXE, archive, executable_location));
		assert(c_res and c_code == 0, 'copy command encountered an error');
		fsExists(executable_location, 'file', 'failed to find file ('..filename..') after copy');
		print('Deleting archive...');
		assert(uv.fs_unlink(archive));
	end;
end;

local copyLove2DFiles = function()
	local n = #LOVE2D_FILES;
	for i = 1, n do
		local filename = LOVE2D_FILES[i];
		local file_path = path.join(LOVE2D, filename);
		local build_path = path.join(BUILD_NAME, filename);
		print('Checking file ('..filename..') in Love2D directory');
		fsExists(file_path, 'file', 'file ('..filename..') not found in Love2D directory');
		print('Copying file ('..filename..')');
		qexecute(format(COPY_FORMAT, file_path, build_path));
		fsExists(build_path, 'file', 'failed to find file ('..filename..') after copy');
		print('Copy found at', build_path..'\n');
	end;
end;

local copyGameLibs = function()
	scanDirectory('.', function(dir, filename)
		if (path.extname(filename) == LIBRARY_EXT) then
			local full_path = path.join(dir, filename);
			local build_path = path.join(BUILD_NAME, filename);
			print('Copying file ('..filename..')', full_path, build_path);
			qexecute(format(COPY_FORMAT, full_path, build_path));
			fsExists(build_path, 'file', 'failed to find file ('..filename..') after copy');
			print('Copy found at', build_path..'\n');
		end;
	end);
end;

coroutine.wrap(function()
	local version_display = format(VERSION_FORMAT, bin_package.version);
	uv.set_process_title(version_display);
	print(format(SPLIT_FORMAT, version_display));
	print(format(REPO_FORMAT, bin_package.homepage));
	print('Operating System: '..system_os..' '..system_arch);
	assert(system_os == 'Windows', 'windows only executable');
	print(format(SPLIT_FORMAT, 'Clearing old build'));
	clear();
	print(format(SPLIT_FORMAT, 'Checking for dependencies'));
	prepare();
	print(format(SPLIT_FORMAT, 'Creating .love'));
	local archive = createLoveArchive();
	print(format(SPLIT_FORMAT, 'Creating executable'));
	createExecutable(archive);
	print(format(SPLIT_FORMAT, 'Importing Love2D files'));
	copyLove2DFiles();
	print(format(SPLIT_FORMAT, 'Importing Libraries'));
	copyGameLibs();
	print(format(SPLIT_FORMAT, 'done'));
	print('Build located at '..uv.fs_realpath(BUILD_NAME));
end)();

uv.run();