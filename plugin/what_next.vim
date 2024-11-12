if exists('g:loaded_what_next') | finish | endif " prevent loading file twice

let s:save_cpo = &cpo " save user coptions
set cpo&vim " reset them to defaults

" mapping smallest range to 'o'
inoremap <C-o> <CMD>lua require("what_next").predict_next_edit()<CR>


let &cpo = s:save_cpo " and restore after
unlet s:save_cpo

let g:loaded_what_next = 1
