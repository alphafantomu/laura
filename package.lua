return {
	name = 'alphafantomu/laura',
	version = '0.0.6',
	description = 'A binary that exports your Love2D games for distribution',
	tags = {'love2d', 'build', 'export', 'distribution'},
 	license = 'MIT',
	author = {name = 'Ari Kumikaeru'},
	homepage = 'https://github.com/alphafantomu/laura',
	dependencies = {
		'luvit/require';
		'luvit/path';
		'alphafantomu/discordia-extensions';
    },
    files = {
		'**.lua',
		'!deps'
	}
}