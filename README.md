# tmux-easymotion
[![Build Status](https://travis-ci.org/schasse/tmux-easymotion.svg?branch=master)](https://travis-ci.org/schasse/tmux-easymotion)

[easymotion](https://github.com/easymotion/vim-easymotion) for tmux.


## Requirements

* [tpm](https://github.com/tmux-plugins/tpm)
* ruby

## Installation

Add plugin to the list of TPM plugins in `~/.tmux.conf`:

```
set -g @plugin 'schasse/tmux-easymotion'
```
Hit `tmux-prefix` + <kbd>I</kbd> to fetch the plugin and source it. You should now be able to use the plugin.

## Usage

* `tmux-prefix` + <kbd>j</kbd>
* `<first letter of the word to jump to>`
