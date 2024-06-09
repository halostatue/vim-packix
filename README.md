# packix: A Vim 9+ Plugin Manager

packix is yet another plugin manager for Vim. It _does not_ support Neovim and
never will. Use [lazy.nvim][lazy.nvim] if you must use Neovim.

I am not using it yet, so I recommend you look elsewhere, maybe
[vim-packager][vim-packager] (the migration will not be effortless, but it
_will_ be smaller than from any other plugin manager).

## Requirements

- Vim 9 or later
- Git
- macOS, Windows, or Linux

> Testing is performed on my machine, with MacVim 9.1 on macOS 14.5. I may do
> some basic testing on an Alpine Linux Docker image, but that is ongoing.

## Installation

```console
# Linux, macOS, *BSD, and WSL
git clone https://github.com/halostatue/vim-packix ~/.vim/pack/packix/opt/vim-packix

# Windows
git clone https://github.com/halostatue/vim-packix ~/vimfiles/pack/packix/opt/vim-packix
```

### Automatic Installation

Automatic installation can be done with a bit of scripting in your `vimrc`. The
script below will add `~/.local/share/vim/site` to `&packpath`, and on startup
will check to see if packix is installed and clone it to
`~/.local/share/vim/site/packix/opt/vim-packix` if not.

```vim
vim9script

const xdg_data_path = exists('$XDG_DATA_PATH') ?
    $XDG_DATA_PATH : expand('~/.local/share')
const vim_site = xdg_data_path .. '/vim/site'

if &packpath !~# vim_site
    &packpath = vim_site .. ',' .. &packpath
endif

const pack_root = vim_site .. '/pack/packix/opt'

mkdir(pack_root, 'p')

const packix_path = pack_root .. '/vim-packix'
const packix_url = "https://github.com/halostatue/vim-packix.git"

if has('vim_starting') && !isdirectory(packix_path .. '/.git')
  const command = printf('silent !git clone %s %s', packix_url, packix_path)

  silent execute command

  augroup install-vim-packix
    autocmd!
    autocmd VimEnter * if exists(':PackixInstall') == 2 | PackixInstall | endif
  augroup END
endif
```

## Usage

Using `setup` function.

```vim
if &compatible
  set nocompatible
endif

function! s:packager_init(packager) abort
  call a:packager.add('halostatue/vim-packix', { 'type': 'opt' })
  call a:packager.add('junegunn/fzf', { 'do': './install --all && ln -s $(pwd) ~/.fzf'})
  call a:packager.add('junegunn/fzf.vim')
  call a:packager.add('vimwiki/vimwiki', { 'type': 'opt' })
  call a:packager.add('Shougo/deoplete.nvim')
  call a:packager.add('autozimu/LanguageClient-neovim', { 'do': 'bash install.sh' })
  call a:packager.add('morhetz/gruvbox')
  call a:packager.add('lewis6991/gitsigns.nvim', {'requires': 'nvim-lua/plenary.nvim'})
  call a:packager.add('haorenW1025/completion-nvim', {'requires': [
  \ ['nvim-treesitter/completion-treesitter', {'requires': 'nvim-treesitter/nvim-treesitter'}],
  \ {'name': 'steelsojka/completion-buffers', 'opts': {'type': 'opt'}},
  \ 'kristijanhusak/completion-tags',
  \ ]})
  call a:packager.add('hrsh7th/vim-vsnip-integ', {'requires': ['hrsh7th/vim-vsnip'] })
  call a:packager.local('~/my_vim_plugins/my_awesome_plugin')

  "Provide full URL; useful if you want to clone from somewhere else than GitHub.
  call a:packager.add('https://my.other.public.git/tpope/vim-fugitive.git')

  "Provide SSH-based URL; useful if you have write access to a repository and wish to push to it
  call a:packager.add('git@github.com:mygithubid/myrepo.git')

  "Loaded only for specific filetypes on demand. Requires autocommands below.
  call a:packager.add('kristijanhusak/vim-js-file-import', { 'do': 'npm install', 'type': 'opt' })
  call a:packager.add('fatih/vim-go', { 'do': ':GoInstallBinaries', 'type': 'opt' })
  call a:packager.add('neoclide/coc.nvim', { 'do': function('InstallCoc') })
  call a:packager.add('sonph/onehalf', {'rtp': 'vim/'})
endfunction

packadd vim-packix
call packix#setup(function('s:packager_init'))
```

and run `PackagerInstall` or `PackagerUpdate`. See all available commands
[here](#commands)

Or doing the old way that allows more control.

```vim
if &compatible
  set nocompatible
endif

" Load packager only when you need it
function! PackagerInit() abort
  packadd vim-packix
  call packix#init()
  call packix#add('halostatue/vim-packix', { 'type': 'opt' })
  call packix#add('junegunn/fzf', { 'do': './install --all && ln -s $(pwd) ~/.fzf'})
  call packix#add('junegunn/fzf.vim')
  call packix#add('vimwiki/vimwiki', { 'type': 'opt' })
  call packix#add('Shougo/deoplete.nvim')
  call packix#add('autozimu/LanguageClient-neovim', { 'do': 'bash install.sh' })
  call packix#add('morhetz/gruvbox')
  call packix#add('lewis6991/gitsigns.nvim', {'requires': 'nvim-lua/plenary.nvim'})
  call packix#add('haorenW1025/completion-nvim', {'requires': [
  \ ['nvim-treesitter/completion-treesitter', {'requires': 'nvim-treesitter/nvim-treesitter'}],
  \ {'name': 'steelsojka/completion-buffers', 'opts': {'type': 'opt'}},
  \ 'kristijanhusak/completion-tags',
  \ ]})
  call packix#add('hrsh7th/vim-vsnip-integ', {'requires': ['hrsh7th/vim-vsnip'] })
  call packix#local('~/my_vim_plugins/my_awesome_plugin')

  " Provide full URL; useful if you want to clone from somewhere else than GitHub.
  call packix#add('https://my.other.public.git/tpope/vim-fugitive.git')

  " Provide SSH-based URL; useful if you have write access to a repository and wish to push to it
  call packix#add('git@github.com:mygithubid/myrepo.git')

  " Loaded only for specific filetypes on demand. Requires autocommands below.
  call packix#add('kristijanhusak/vim-js-file-import', { 'do': 'npm install', 'type': 'opt' })
  call packix#add('fatih/vim-go', { 'do': ':GoInstallBinaries', 'type': 'opt' })
  call packix#add('neoclide/coc.nvim', { 'do': function('InstallCoc') })
  call packix#add('sonph/onehalf', {'rtp': 'vim/'})
endfunction

function! InstallCoc(plugin) abort
  exe '!cd '.a:plugin.dir.' && yarn install'
  call coc#add_extension('coc-eslint', 'coc-tsserver', 'coc-pyls')
endfunction

" These commands are automatically added when using `packix#setup()`
command! -nargs=* -bar PackagerInstall call PackagerInit() | call packix#install(<args>)
command! -nargs=* -bar PackagerUpdate call PackagerInit() | call packix#update(<args>)
command! -bar PackagerClean call PackagerInit() | call packix#clean()
command! -bar PackagerStatus call PackagerInit() | call packix#status()

"Load plugins only for specific filetype
"Note that this should not be done for plugins that handle their loading using ftplugin file.
"More info in :help pack-add
augroup packager_filetype
  autocmd!
  autocmd FileType javascript packadd vim-js-file-import
  autocmd FileType go packadd vim-go
augroup END

"Lazy load plugins with a mapping
nnoremap <silent><Leader>ww :unmap <Leader>ww<BAR>packadd vimwiki<BAR>VimwikiIndex<CR>
```

After that, reload your `vimrc`, and run `:PackagerInstall`. It will install all
the plugins and run it's hooks.

If some plugin installation (or it's hook) fail, you will get (as much as
possible) descriptive error on the plugin line. To view more, press `E` on the
plugin line to view whole stdout.

### Functions

#### `packix#setup(callback_function, opts)`

This is a small wrapper around functions explained below. It does this:

1. Adds all necessary commands. `PackagerInstall`, `PackagerUpdate`,
   `PackagerClean` and `PackagerStatus`
2. Running any of the command does this:

   - calls `packix#init(opts)`
   - calls provided `callback_function` with `packager` instance
   - calls proper function for the command

#### `packix#init(options)`

Available options:

- `depth` - `--depth` value to use when cloning. Default: `5`
- `jobs` - Maximum number of jobs that can run at same time. `0` is treated as
  unlimited. Default: `8`
- `dir` - Directory to use for installation. By default uses `&packpath` value,
  which is `~/.vim/pack/packager` in Vim, and `~/.config/nvim/pack/packager` in
  Neovim.
- `window_cmd` - What command to use to open packager window. Default:
  `vertical topleft new`
- `default_plugin_type` - Default `type` option for plugins where it's not
  provided. More info below in `packix#add` options. Default: `start`
- `disable_default_mappings` - Disable all default mappings for packager buffer.
  Default: `0`

#### `packix#add(name, options)`

`name` - URL to the git directory, or only last part of it to use `github`.

Example: for GitHub repositories, `halostatue/vim-packix` is enough, for
something else, like `bitbucket`, use full path
`https://bitbucket.org/owner/package`

Options:

- `name` - Custom name of the plugin. If omitted, last part of the URL explained
  above is taken (example: `vim-packix`, in `halostatue/vim-packix`)
- `type` - In which folder to install the plugin. Plugins that are loaded on
  demand (with `packadd`), goes to `opt` directory, where plugins that are auto
  loaded goes to `start` folder. Default: `start`
- `branch` - git branch to use. Default: '' (Uses the default from the
  repository, usually master)
- `tag` - git tag to use. Default: ''
- `rtp` - Used in case when subdirectory contains vim plugin. Creates a
  symbolink link from subdirectory to the packager folder. If `type` of package
  is `opt` use `packadd {packagename}__{rtp}` to load it (example:
  `packadd onehalf__vim`)
- `commit` - exact git commit to use. Default: '' (Check below for priority
  explanation)
- `do` - Hook to run after plugin is installed/updated: Default: ''. Examples
  below.
- `frozen` - When plugin is frozen, it is not being updated. Default: 0
- `requires` - Dependencies for the plugin. Can be
  - _string_ (ex. `'halostatue/vim-packix'`)
  - _list_ (ex. `['halostatue/vim-packix', {'type': 'opt'}]`)
  - _dict_ (ex. `{'name': 'halostatue/vim-packix', 'opts': {'type': 'opt'} }`).
    See example `vimrc` above.

`branch`, `tag` and `commit` options go in certain priority:

- `commit`
- `tag`
- `branch`

Hooks can be defined in 3 ways:

1. As a string that **doesn't** start with `:`. This runs the command as it is a
   shell command, in the plugin directory. Example:

   ```vimL
   call packix#add('junegunn/fzf', { 'do': './install --all'})
   call packix#add('kristijanhusak/vim-js-file-import', { 'do': 'npm install' })
   ```

2. As a string that starts with `:`. This executes the hook as a vim command.
   Example:

   ```vimL
   call packix#add('fatih/vim-go', { 'do': ':GoInstallBinaries' })
   call packix#add('iamcco/markdown-preview.nvim' , { 'do': ':call mkdp#util#install()' })
   ```

3. As a `funcref` that gets the plugin info as an argument. Example:

   ```vimL
   call packix#add('iamcco/markdown-preview.nvim' , { 'do': { -> mkdp#util#install() } })
   call packix#add('junegunn/fzf', { 'do': function('InstallFzf') })

   function! InstallFzf(plugin) abort
     exe a:plugin.dir.'/install.sh --all'
   endfunction
   ```

#### `packix#local(name, options)`

**Note**: This function only creates a symbolic link from provided path to the
packager folder.

`name` - Full path to the local folder Example: `~/my_plugins/my_awesome_plugin`

Options:

- `name` - Custom name of the plugin. If omitted, last part of path is taken
  (example: `my_awesome_plugin`, in `~/my_plugins/my_awesome_plugin`)
- `type` - In which folder to install the plugin. Plugins that are loaded on
  demand (with `packadd`), goes to `opt` directory, where plugins that are auto
  loaded goes to `start` folder. Default: `start`
- `do` - Hook to run after plugin is installed/updated: Default: ''
- `frozen` - When plugin is frozen, it is not being updated. Default: 0

#### `packix#install(opts)`

This only installs plugins that are not installed.

Available options:

- `on_finish` - Run command after installation finishes. For example to quit at
  the end: `call packix#install({ 'on_finish': 'quitall' })`
- `plugins` - Array of plugin names to install. Example:
  `call packix#install({'plugins': ['gruvbox', 'gitsigns.nvim']})`

When installation finishes, there are two mappings that can be used:

- `D` - Switches view from installation to status. This prints all plugins, and
  it's status (Installed, Updated, list of commits that were pulled with latest
  update)
- `E` - View stdout of the plugin on the current line. If one of the
  installations presented an error (from installation or post hook), it's
  printed in the preview window.

#### `packix#update(opts)`

This installs plugins that are not installed, and updates existing one to the
latest (if it's not marked as frozen).

Available options:

- `on_finish` - Run command after update finishes. For example to quit at the
  end: `call packix#update({ 'on_finish': 'quitall' })`
- `force_hooks` - Force running post hooks for each package even if up to date.
  Useful when some hooks previously failed. Must be non-empty value:
  `call packix#update({ 'force_hooks': 1 })`
- `plugins` - Array of plugin names to update. Example:
  `call packix#update({'plugins': ['gruvbox', 'gitsigns.nvim']})`

When update finishes, there are two mappings that can be used:

- `D` - Switches view from installation to status. This prints all plugins, and
  it's status (Installed, Updated, list of commits that were pulled with latest
  update)
- `E` - View stdout of the plugin on the current line. If one of the updates
  presented an error (from installation or post hook), it's printed in the
  preview window.

#### `packix#status()`

This shows the status for each plugin added from `vimrc`.

You can come to this view from Install/Update screens by pressing `D`.

Each plugin can have several states:

- `Not installed` - Plugin directory does not exist. If something failed during
  the clone process, shows the error message that can be previewed with `E`
- `Install/update failed` - Something went wrong during installation/updating of
  the plugin. Press `E` on the plugin line to view stdout of the process.
- `Post hook failed` - Something went wrong with post hook. Press `E` on the
  plugin line to view stdout of the process.
- `OK` - Plugin is properly installed and it doesn't have any update
  information.
- `Updated` - Plugin has some information about the last update.

#### `packix#clean()`

This removes unused plugins. It will ask for confirmation before proceeding.
Confirmation allows selecting option to delete all folders from the list
(default action), or ask for each folder if you want to delete it.

### `Commands`

Commands are added only when using `packix#setup`. `require('packager').setup()`

- PackagerInstall - same as
  [packix#install(`<args>`)](https://github.com/halostatue/vim9-packix#packagerinstallopts).
- PackagerUpdate - same as
  [packix#update(`<args>`)](https://github.com/halostatue/vim9-packix#packagerupdateopts).
  Note that args are passed as they are written. For example, to force running
  hooks you would do `:PackagerUpdate {'force_hooks': 1}`
- PackagerClean - same as
  [packix#clean()](https://github.com/halostatue/vim9-packix#packagerclean)
- PackagerStatus - same as
  [packix#status()](https://github.com/halostatue/vim9-packix#packagerstatus)

## Configuration

Several buffer mappings are added for packager buffer by default:

- `q` - Close packager buffer (`<Plug>(PackagerQuit)`)
- `<CR>` - Preview commit under cursor (`<Plug>(PackagerOpenSha)`)
- `E` - Preview stdout of the installation process of plugin under cursor
  (`<Plug>(PackagerOpenStdout)`)
- `<C-j>` - Jump to next plugin (`<Plug>(PackagerGotoNextPlugin)`)
- `<C-k>` - Jump to previous plugin (`<Plug>(PackagerGotoPrevPlugin)`)
- `D` - Go to status page (`<Plug>(PackagerStatus)`)
- `O` - Open details of plugin under cursor (`<Plug>(PackagerPluginDetails)`)

To use a different mapping for any of these, create a `filetype` autocommand
with the mapping. For example, to use `<c-h>` instead of `<c-j>` for jumping to
next plugin, add this to `vimrc`:

```VimL
autocmd FileType packager nmap <buffer> <C-h> <Plug>(PackagerGotoNextPlugin)
```

## Why?

As [Kristijan Husak][@kristijanhusak] [said][vim-packager-why]:

> There's a lot of plugin managers for Vim out there.

This was true when originally written in 2018 and it is still true now. There's
[vim-plug][vim-plug], [vim-packager][vim-packager], [minpac][minpac], and
[vim-jetpack][vim-jetpack] – all of which work with both Vim and Neovim. There
are more that are Neovim-only, the best of which is currently considered
[lazy.nvim][lazy.nvim].

I recently noticed that [@kristijanhusak][@kristijanhusak] archived
[vim-packager][vim-packager] in March 20204, which was my preferred package
manager for Vim (on Neovim, in the rare times I use it, I manage plugins with
[lazy.nvim][lazy.nvim]). I tried [vim-jetpack][vim-jetpack], but found that it
did not work with some packages which _should_ be in `pack/*/start` instead of
`pack/*/opt` (vim-jetpack installs everything into `pack/*/opt` and appears to
run `packadd …` for non-optional plugins).

I have been looking for an excuse to play with [Vim 9 script][vim9script], so I
decided to fork vim-packager and rewrite it. The Neovim developers made
decisions at the beginning which have — a decade on — ensured that there will
never be a GUI interface which is as usable as gvim or [MacVim.app][macvim.app].
Since MacVim.app is a core part of my workflow, I have no need for a nominally
cross-editor plugin manager.

Ultimately, the answer to "Why?" is "I wanted to".

## Thanks to:

- [@kristijanhusak][@kristijanhusak] and [vim-packager][vim-packager] for the
  baseline code.
- [@k-takata][@k-takata] and his [minpac][minpac] plugin for inspiration and
  parts

## Alternate Installation

This installation method is experimental and may be removed in the future. Note
that the destination directory _differs_ from the primary installation
directory.

```console
# Linux, macOS, WSL, *BSD, etc.
curl -fSSLo ~/.vim/pack/vim-packix/opt/vim-packix/import/packix.vim \
    https://raw.githubusercontent.com/halostatue/vim-packix/main/import/packix.vim

# Windows
curl -fSSLo ~/vimfiles/pack/vim-packix/opt/vim-packix/import/packix.vim \
    https://raw.githubusercontent.com/halostatue/vim-packix/main/import/packix.vim
```

When installing with this method, the following features are unavailable:

- `halostatue/vim-packix` may not be added to the package list;
- the |autoload-functions| `packix#*` are not available;
- this help documentation is not available; and
- updates must be installed manually using the install method.

[@k-takata]: https://github.com/k-takata
[@kristijanhusak]: https://github.com/kristijanhusak
[lazy.nvim]: https://github.com/folke/lazy.nvim
[macvim.app]: https://github.com/macvim-dev/macvim
[minpac]: https://github.com/k-takata/minpac
[vim-jetpack]: https://github.com/tani/vim-jetpack
[vim-packager-why]: https://github.com/kristijanhusak/vim-packager?tab=readme-ov-file#why
[vim-packager]: https://github.com/kristijanhusak/vim-packager
[vim-plug]: https://github.com/junegunn/vim-plug
[vim9script]: https://vimhelp.org/vim9.txt.html
