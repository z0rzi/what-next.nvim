if exists('g:loaded_what_next') | finish | endif " prevent loading file twice

let s:save_cpo = &cpo " save user coptions
set cpo&vim " reset them to defaults

" mapping smallest range to 'o'
nnoremap <C-l> <CMD>lua require("what-next").predict_next_edit(false)<CR>
vnoremap <C-l> <ESC>:lua require("what-next").predict_next_edit(true)<CR>


let &cpo = s:save_cpo " and restore after
unlet s:save_cpo

let g:loaded_what_next = 1
