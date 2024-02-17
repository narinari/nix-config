{ _, ... }:

{
  home.sessionVariables = {
    EMACS = "emacsclient -nw -a 'emacs -nw'";
    EDITOR = "emacsclient -nw -a 'emacs -nw'";
    VISUAL = "emacsclient -nw -a 'emacs -nw'";
  };
}
