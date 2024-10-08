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

As packix is written with |vim9| script, it offers typed functions for use with
`vim9script` configuration files, and `autoload`-scripts for use with old-style
scripts.

Package selection is offered through either `Setup` or `Init`, offering
different levels of control.

After either has been set up, reload your `vimrc` and run `:PackixInstall`,
which will install the selected plugins and run any post-install hooks required.

If a plugin's installation or hook fails, the plugin line in the output window
will include the most recent output line. To view more, press `E` on the plugin
line to view the whole output for the failed step.

### Setup

The `Setup` function adds `:PackixInstall`, `:PackixUpdate`, `:PackixClean`, and
`:PackixStatus` commands that use a callback `Funcref` or lambda to configure
and run the packix manager. The only parameter to the callback is the packix
manager instance.

Using `vim9script`:

```vim
vim9script

packadd vim-packix
import autoload 'packix.vim'

packix.Setup((px: packix.Manager) => {
  px.Add('halostatue/vim-packix', { type: 'opt' })
  px.Add('junegunn/fzf.vim', {
    requires: {
      url: 'junegunn/fzf',
      opts: { do: './install --all && ln -s $(pwd) ~/.fzf' }
    }
  })
  px.Add('vimwiki/vimwiki', { type: 'opt' })
  px.Add('morhetz/gruvbox')
  px.Add('hrsh7th/vim-vsnip-integ', { requires: ['hrsh7th/vim-vsnip'] })
  px.Local('~/my_vim_plugins/my_awesome_plugin')

  # Provide full URL; useful if you want to clone from somewhere else than
  # GitHub.
  px.Add('https://my.other.public.git/tpope/vim-fugitive.git')

  # Provide SSH-based URL; useful if you have write access to a repository
  # and wish to push to it
  px.Add('git@github.com:mygithubid/myrepo.git')

  # Loaded only for specific filetypes on demand.
  # Requires autocommand definitions to run `packadd` as required, see
  # below for examples.
  px.Add('kristijanhusak/vim-js-file-import', {
    do: 'npm install', type: 'opt'
  })
  px.Add('fatih/vim-go', { do: ':GoInstallBinaries', type: 'opt' })
  px.Add('neoclide/coc.nvim', { do: function('InstallCoc') })
  px.Add('sonph/onehalf', { rtp: 'vim/' })
})

augroup packix_filetype
  autocmd!
  autocmd FileType javascript packadd vim-js-file-import
  autocmd FielType go packadd vim-go
augroup END
```

Using legacy Vim script:

```vim
scriptencoding utf-8

if &compatible
  set nocompatible
endif

packadd vim-packix

call packix#Setup({ packix ->
  px.Add('halostatue/vim-packix', { 'type': 'opt' })
  px.Add('junegunn/fzf.vim',
        \ {
        \   'requires': {
        \     'url': 'junegunn/fzf',
        \     'opts': { 'do': './install --all && ln -s $(pwd) ~/.fzf' }
        \   }
        \ })
  px.Add('vimwiki/vimwiki', { 'type': 'opt' })
  px.Add('morhetz/gruvbox')
  px.Add('hrsh7th/vim-vsnip-integ', { 'requires': ['hrsh7th/vim-vsnip'] })
  px.Add('~/my_vim_plugins/my_awesome_plugin')

  " Provide full URL; useful if you want to clone from somewhere else than
  GitHub.
  px.Add('https://my.other.public.git/tpope/vim-fugitive.git')

  " Provide SSH-based URL; useful if you have write access to a repository
  and " wish to push to it
  px.Add('git@github.com:mygithubid/myrepo.git')

  " Loaded only for specific filetypes on demand.
  " Requires autocommand definitions to run `packadd` as required, see
  below for " examples.
  px.Add('kristijanhusak/vim-js-file-import',
        \ { 'do': 'npm install', 'type': 'opt' })
  px.Add('fatih/vim-go', { 'do': ':GoInstallBinaries', 'type': 'opt' })
  px.Add('neoclide/coc.nvim', { 'do': function('InstallCoc') })
  px.Add('sonph/onehalf', { 'rtp': 'vim/' })
})

" This could also be done with a function reference:

function! s:packix_init(packix)
  a:packix.Add('vimwiki/vimwiki', { 'type': 'opt' })
endfunction

call packix#Setup(function('s:packix_init'))
```

### `Init`

The `Init` function offers full control and does not define any commands; it is
up to you to define the commands for easy operation.

Using `vim9script`:

```vim
vim9script

def PackixInit()
  packadd vim-packix
  import autoload 'packix.vim'

  packix.Init()
  packix.Add('halostatue/vim-packix', { type: 'opt' })
  packix.Add('vimwiki/vimwiki', { type: 'opt' })
enddef

command! -nargs=* -bar PackixInstall <Cmd>PackixInit() | call packix#Install(<args>)
command! -nargs=* -bar PackixUpdate <Cmd>PackixInit() | call packix#Update(<args>)
command! -bar PackixClean <Cmd>PackixInit() | call packix#Clean()
command! -bar PackixStatus <Cmd>PackixInit() | call packix#Status()
```

## Functions

All of the functions documented here are available via import-autoload or
through autoload prefixes (`packix#`). Using legacy Vim script, read
|legacy-import| for how to use imports. In the examples below, the Vim 9 script
(assuming `import autoload 'packix.vim'`) and autoload functions versions are
shown.

### `packix.Setup()` `packix#Setup()`

```
packix#Setup({Callback}: string | Funcref, [opts]: dict<any> = {}): void
packix.Setup({Callback}: string | Funcref, [opts]: dict<any> = {}): void
```

This is a small wrapper around `packix.Init()` and related functions, described
below. It does the following:

- adds commands `:PackixInstall`, `:PackixUpdate`, `:PackixClean`, and
  `:PackixStatus`;
- calls `packix.Init(opts)` when one of the commands above is run;
- calls the provided `Callback` with the `packix.Manager` instance; and
- calls the appropriate function for the command (`packix.Install()`,
  `packix.Update()`, `packix.Clean()`, or `packix.Status()`).

If the `{Callback}` parameter is a String, `packix.Setup` will attempt to create
a `Funcref` from it. See `packix.Init()` for the possible keys and values of the
`opts` parameter.

### `packix.Init()` `packix#Init()`

```
packix.Init([opts]: dict<any> = {}): void
packix#Init([opts]: dict<any> = {}): void
```

Initializes the `packix.Manager` instance. The main configuration `opts` are:

- `depth` (`Number`, default `5`): The `--depth` value to use when cloning.

- `jobs` (`Number`, default `8`): The maximum number of jobs that can run at the
  same time, where `0` is treated as unlimited.

- `window_cmd` (`String`, default `vertical topleft new`): The command to use to
  open the packix window.

Secondary `opts` supported but discouraged from use are:

- `dir` (`String`, default special): The directory to use for package
  installation. By default the `dir` is derived from the first directory from
  `'packpath'`, which is `~/vimfiles/pack/packix` on Windows or
  `~/.vim/pack/packix` everywhere else.

  The `packix` directory _must_ be found in `'packpath'`, so if you wish to use
  a directory _other_ than `~/.vim/pack/packix`, it is better to modify
  `'packpath'` so that your target directory is first:

  ```vim
  if &packpath !~# expand("$HOME/.local/share/vim/site,")
    &packpath = expand("$HOME/.local/share/vim/site,") .. &packpath
  end
  ```

- `default_plugin_type` (`String`, default `start`, allowed `opt` or `start`):
  The `type` option for plugins when not provided. More details can be found in
  `packix.Add()`.

- `disable_default_mappings` (`Boolean`, default `false`): If `true`, all
  default mappings for the packix buffer are disabled.

### `packix.Add()` `packix#Add()`

```
packix.Add({url}: string, [opts]: dict<any> = {}): void
packix#Add({url}: string, [opts]: dict<any> = {}): void
```

Adds the plugin found at `url` with `opts` The `url` may be a shorthand value,
`owner/repo`, which is expanded to `https://github.com/owner/repo`. Full URLs
may be provided to clone from hosts other than GitHub
(`https://bitbucket.org/owner/repo.git`) and SSH-based URLs may be provided
(`git@github.com:owner/repo.git`), which would allow read/write access.

Installation `opts` may also be provided:

- `name` (`String`, default special): An optional custom name for the plugin. If
  omitted, the name is derived from the last part of the URL parameter
  (`halostatue/vim-packix` becomes `vim-packix`;
  `https://bitbucket.org/owner/repo.git` becomes `repo`).

- `type` (`String`, default special, allowed `opt` or `start`): The folder `opt`
  or `start` where the plugin will be installed. On-demand plugins, loaded with
  `packadd plugin-name` are installed into the `opt` directory, whereas
  autoloaded plugins are in `start`. The default comes from the owning
  `packix.Manager` instance (which itself defaults to `start`).

- `commit` (`String`): The optional git commit to checkout on install or update.
  Higher priority than `tag` or `branch`.

- `tag` (`String`): The optional git tag to checkout on install or update.
  Higher priority than `branch`.

- `branch` (`String`): The optional git branch to checkout on install or update.
  Lowest priority, defaulting to the repository default branch.

- `rtp` (`String`): A custom `'runtimepath'` used with some repositories
  (usually colour schemes) where the associated Vim plugin is in a subdirectory.
  Packix creates a symbolic link from the specified subdirectory to the packix
  plugin folder.

  If the `type` of the package is `opt`, then the command to load the plugin is
  `packadd {plugin}__{rtp}` instead of just `packadd {plugin}`:

  ```vim
  packix.Add('sonph/onehalf', { rtp: 'vim/', type: 'opt' })
  packadd onehalf__vim
  ```

- `do` (`String` or `Funcref`): The Hook to run after the plugin is installed or
  updated. See examples below.

- `frozen` (`Boolean`, default `false`): If `true`, the plugin is frozen and
  will not be updated after install.

- `requires` (special): Plugins may have other plugins that they depend on. The
  value of `requires` _should_ be a list, but if there is only one dependency it
  may be specified without using a list. The values within the `requires` list
  may be either `String` (the plugin URL, like `'vimwiki/vimwiki'`) or a `Dict`
  with `url` and `opts` keys
  (`{ url: 'vimwiki/vimwiki', opts: { type: 'opt' }`). Required plugins do not
  inherit any options from the parent.

- `on` (special): On-demand plugins (`{ type: 'opt' }`) can be loaded with the
  command (`String`) or commands (`List` of `String`) specified in this option.
  The `on` option is ignored if the plugin `type` is 'start'.

  ```vim
  packix.Add('tpope/vim-rake', { type: 'opt', on: 'Rake' })
  packix.Add('tpope/vim-rails',
          { type: 'opt', on: ['Rails', 'Generate', 'Runner'] })
  ```

#### Post-install Hooks

Post-install `do` hooks can be defined in three ways:

1. As a `Funcref` that takes the plugin info as an argument.

   ```vim
   packix.Add('junegunn/fzf',
       { do: (plugin) => exe plugin.dir .. '/install.sh --all' })
   packix.Add('junegunn/fzf', { do: function('InstallFzf') })

   def InstallFzf(plugin: packix.Plugin)
     exe plugin.dir .. '/install.sh --all'
   enddef
   ```

2. As a `String` that starts with `:`, indicating a Vim command to run.

   ```vim
   packix.Add('fatih/vim-go', { do: ':GoInstallBinaries' })
   ```

3. As a `String` that does not start with `:`, indicating a command to run as a
   shell command in the plugin directory.

   ```vim
   packix.Add('junegunn/fzf', { do: './install --all'})
   packix.Add('kristijanhusak/vim-js-file-import', { do: 'npm install' })
   ```

### `packix.Local()` `packix#Local()`

```
packix.Local({path}: string, [opts]: dict<any> = {}): void
packix#Local({path}: string, [opts]: dict<any> = {}): void
```

A variant of `packix.Add()` that creates a symbolic link from the provided
{path} to the packix folder in `'packpath'`. The `path` must be a `String` full
path to the local folder, such as `~/my_plugins/my_awesome_plugin`.

The `opts` available for installation. See `packix.Add()` for full details.
While all options can be specified, only the options `name`, `type`, `do`, and
`frozen` have any impact on local plugins.

### `packix.Install()` `packix#Install()`

```
packix.Install([opts]: dict<any> = {}): void
packix#Install([opts]: dict<any> = {}): void
```

Installs plugins that are not currently installed.

Available `opts` are:

- `on_finish` (`String`): The Vim command to run after installation finishes.
  Example: `packix.Install({ on_finish: 'quitall' })` will quit Vim after
  installation completes.

- `plugins` (`List` of `String`): The list of plugins to install if they are not
  already installed. Any plugins not in this list will be ignored. Example:
  `packix.Install({ plugins: ['gruvbox', 'vim-signify'] })` will only install
  `gruvbox` and `vim-signify` if they are not already installed.

After installation finishes, two mappings are added to the packix buffer:

- `D`: Switches view from installation to status. This prints all plugins and
  the status of each (Installed, Updated, list of commits that were pulled with
  latest update).

- `E`: Views the output of the plugin on the current line. If one of the install
  or post-install hooks presented an error, this is shown in the preview window.

### `packix.Update()` `packix#Update()`

```
packix.Update([opts]: dict<any> = {}): void
packix#Update([opts]: dict<any> = {}): void
```

Installs plugins not currently installed and updates existing plugins to the
latest version (unless the plugin is `frozen`).

Available `opts` are:

- `on_finish` (`String`): The Vim command to run after update finishes. Example:
  `packix.Update({ on_finish: 'quitall' })` will quit Vim after updates
  complete.

- `force_hooks` (`Boolean`, default: `false`): Forces `do` hooks to run for each
  package even if it is up to date. This is useful when some hooks previously
  failed. `packix.Update({ force_hooks: true })`

- `plugins` (`List` of `String`): The list of plugins to update. Any plugins not
  in this list will be ignored. Example:
  `packix.Install({ plugins: ['gruvbox', 'vim-signify'] })` will only update or
  install `gruvbox` and `vim-signify`.

After update finishes, two mappings are added to the packix buffer:

- `D`: Switches view from update to status. This prints all plugins and the
  status of each (Installed, Updated, list of commits that were pulled with
  latest update).

- `E`: Views the output of the plugin on the current line. If one of the update
  or post-update hooks presented an error, this is shown in the preview window.

### `packix.Status()` `packix#Status()`

```
packix.Status(): void
packix#Status(): void
```

Shows the status for each plugin added from the Vim configuration (`vimrc`).
This view is reachable from the Install and Update screens by pressing `D`.

Each plugin can have several states:

- `Not installed`: the plugin directory does not exist. If something failed
  during the clone process, an error message is shown and the full output can be
  previewed with `E`.

- `Install/update failed`: something went wrong during install or update of the
  plugin. Press `E` on the plugin line to view output of the process.

- `Hook failed`: something went wrong with post install/update hook. Press `E`
  on the plugin line to view output of the process.

- `OK`: Plugin is properly installed and it doesn't have any update information.

- `Updated`: Plugin has some information about its last update.

### `packix.Clean()` `packix#Clean()`

```
packix.Clean(): void
packix#Clean(): void
```

Removes unused plugins, prompting for confirmation before proceeding.
Confirmation options include deleting all folders or prompting for each folder.

### `packix.Plugins()` `packix#Plugins()`

```
packix.Plugins(): list<packix.PluginInfo>
packix#Plugins(): list<packix#PluginInfo>
```

Returns a simplified, read-only version of plugin details, containing `name`,
`type`, `url`, `dir`, `rev`, `headRef`, `installed`, `isLocal`, `mainBranch`,
and `rtpDir`.

### `packix.PluginNames()` `packix#PluginNames()`

```
packix.PluginNames(): list<string>
packix#PluginNames(): list<string>
```

Returns a list of defined plugin names. These may or may not be installed.

### `packix.GetPlugin()` `packix#GetPlugin()`

```
packix.GetPlugin({name}: string): packix.PluginInfo
packix#GetPlugin({name}: string): packix#PluginInfo
```

Gets the plugin info for a plugin identified by {name}, which may be either the
plugin URL, a GitHub shorthand URL, or the resolved plugin name.

```vim
packix.GetPlugin('fatih/vim-go')
packix.GetPlugin('https://github.com/fatih/vim-go')
packix.GetPlugin('vim-go')<
```

### `packix.HasPlugin()` `packix#HasPlugin()`

```
packix.HasPlugin({name}: string): bool
packix#HasPlugin({name}: string): bool
```

Returns `true` if a plugin identified by `name` is defined, which may be either
the plugin URL, a GitHub shorthand URL, or the resolved plugin name.

```vim
packix.HasPlugin('fatih/vim-go')
packix.HasPlugin('https://github.com/fatih/vim-go')
packix.HasPlugin('vim-go')
```

### `packix.IsPluginInstalled()` `packix#IsPluginInstalled()`

```
packix.IsPluginInstalled({name}: string): bool
packix#IsPluginInstalled({name}: string): bool
```

Returns `true` if a plugin identified by `name` is both defined and currently
installed, which may be either the plugin URL, a GitHub shorthand URL, or the
resolved plugin name.

```vim
packix.IsPluginInstalled('fatih/vim-go')
packix.IsPluginInstalled('https://github.com/fatih/vim-go')
packix.IsPluginInstalled('vim-go')
```

### `packix.Version()` `packix#Version()`

```
packix.Version(): string
packix#Version(): string
```

Returns the current packix version.

## Commands

Commands are only added when using `packix.Setup`. For `:PackixInstall` and
`:PackixUpdate`, arguments are passed as written.

### `:PackixInstall`

```vim
:PackixInstall [opts]
```

Sets up Packix and runs `packix.Install()`.

`:PackixInstall { 'on_finish': 'quitall' }` is the same as
`:call packix#Install({ 'on_finish': 'quitall' }).`

### `:PackixUpdate`

```vim
:PackixUpdate [opts]
```

Sets up Packix and runs `packix.Update()`.

`:PackixUpdate { 'on_finish': 'quitall' }` is the same as
`:call packix#Update({ 'on_finish': 'quitall' }).`

### `:PackixClean`

```vim
:PackixClean
```

Sets up Packix and runs `packix.Clean()`.

### `:PackixStatus`

```vim
:PackixStatus
```

Sets up Packix and runs `packix.Status()`.

## Keybindings

When the `packix` buffer is created on `packix.Install()`, `packix.Update()`, or
`packix.Status()`, several mappings are added if they do not already exist.

- `q` => `<Plug>(PackixQuit)`: Close the packix buffer

- `<CR>` => `<Plug>(PackixOpenSha)`: Open a preview window with the commit
  referenced under the cursor.

- `E` => `<Plug>(PackixOpenOutput)`: Open a preview window with the output of
  install/update or post-install/update hook.

- `<C-j>` => `<Plug>(PackixGotoNextPlugin)`: Jumps to the next plugin

- `<C-k>` => `<Plug>(PackixGotoPrevPlugin)`: Jumps to the previous plugin

- `D` => `<Plug>(PackixStatus)`: Opens the status page

- `O` => `<Plug>(PackixPluginDetails)`: Open a preview window for the details of
  the plugin under the cursor.

These mappings can be overridden by adding a `FileType` autocommand with the
mapping. For example, to use `<C-h>` and `<C-l>` for navigating plugins, this
would be added to your `vimrc`:

```vim
autocmd FileType packix nmap <buffer> <C-h> <Plug>(PackagerGotoNextPlugin)
autocmd FileType packix nmap <buffer> <C-l> <Plug>(PackagerGotoPrevPlugin)
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

### Thanks to:

- [@kristijanhusak][@kristijanhusak] and [vim-packager][vim-packager] for the
  baseline code.
- [@k-takata][@k-takata] and his [minpac][minpac] plugin for inspiration and
  parts

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
