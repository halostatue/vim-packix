if &runtimepath !~? $PWD
  let &runtimepath = $PWD .. ',' .. &runtimepath
endif

" source plugin/packager9.vim
" Bufferize messages
