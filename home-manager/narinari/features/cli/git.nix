{ pkgs, config, ... }:

{
  home.packages = with pkgs; [
    bfg-repo-cleaner
    gitAndTools.git-absorb
    gitAndTools.gitui
    gitAndTools.git-machete
    gitAndTools.git-secrets
    git-filter-repo
    gitAndTools.gh
    colordiff
    delta
    tcpdump
    ghq
    gst
  ];

  xdg.configFile = {
    "git/ignore".source = ./git/ignore;
    "git/commit-template".source = ./git/commit-template;
  };

  programs.git = {
    enable = true;
    aliases = {
      alias =
        "!git config --list | grep 'alias\\.' | sed 's/alias\\.\\([^=]*\\)=\\(.*\\)/\\1\\	 => \\2/' | sort";
      add-nowhitespace =
        "!git diff -U0 -w --no-color | git apply --cached --ignore-whitespace --unidiff-zero -";
      s = "status";
      st = "status";
      ss = "status -s";
      sh = "show";
      so = "remote show origin";
      ft = "fetch";
      ftp = "fetch --prune";
      up = "pull --rebase --autostash"; # pull rebase
      po = "push origin"; # push origin
      pof = "push -f origin"; # force
      pu = "push -u origin"; # push origin and set upstream
      pushall = "!git remote | xargs -L1 git push --all";
      rbm = "rebase --merge master"; # masterへのrebaseはよく使うのでalias
      rbd = "rebase --merge develop";
      rbc = "rebase --continue";
      rba = "rebase --abort";
      rbi = "rebase -i";
      rbi1 = "rebase -i HEAD^";
      rbi2 = "rebase -i HEAD^^";
      rbi3 = "rebase -i HEAD^^^";
      rbi4 = "rebase -i HEAD^^^^";
      rbi5 = "rebase -i HEAD^^^^^";
      mn = "merge --no-ff";
      ad = "add";
      c = "commit";
      ci = "commit -a"; # modifiedなファイルを全てstageへ
      cam = "commit -a --amend"; # 直前のcommitを修正
      co = "checkout";
      cb = "checkout -b"; # branch切ってcheckoutする
      ct = "checkout --track"; # remoteのbranchを追跡
      cm = "checkout master";
      cd = "checkout";
      br = "branch";
      ba = "branch -a"; # originも含めた全てのbranchを表示
      bm = "branch --merged"; # merge済みのbranchを表示
      bn = "branch --no-merged"; # mergeしてないbranchを表示
      bo = "branch -r"; # remote branchを表示
      edit-unmerged =
        "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; $EDITOR `f`";
      wc = "whatchanged"; # logに変更されたファイルも一緒に出す
      l =
        "log --graph -n 20 --pretty=format:'%C(yellow)%h%C(cyan)%d%Creset %s %C(green)- %an, %cD%Creset'";
      ln =
        "log --graph -n 20 --pretty=format:'%C(yellow)%h%C(cyan)%d%Creset %s %C(green)- %an, %cr%Creset' --name-status";
      ls = "log --stat --abbrev-commit"; # logに変更されたファイルも一緒に出す
      lp = "log -p"; # diffも一緒に出す
      la = ''
        log --pretty="format:%ad %C(yellow)%h %C(green)(%an):%Creset %s" --date=short''; # ざっくりログ出す
      lr = "log origin"; # originのlog
      ll =
        "log --date=short --pretty=format:'%Cgreen%h %cd %Cblue%cn%x09%Creset%s'"; # onelineでlogを出す
      oneline = "log --oneline --graph --decorate --all";
      ranking = "shortlog -s -n --no-merges";
      log-graph =
        "log --graph --date=short --pretty=format:'%Cgreen%h %cd %Cblue%cn %Creset%s'";
      graph = "log --decorate --oneline --graph";
      log-all =
        "log --graph --all --color --pretty='%x09%h %cn%x09%s %Cred%d%Creset'";
      lf =
        "!f() { git log --format=oneline --name-only $1\\^..$1 | awk 'NR!=1{print}' ;}; f";
      rhs = "reset --soft HEAD";
      rhs1 = "reset --soft HEAD~";
      rhs2 = "reset --soft HEAD~~";
      rhs3 = "reset --soft HEAD~~~";
      rhs4 = "reset --soft HEAD~~~~";
      rhs5 = "reset --soft HEAD~~~~~";
      rhh = "reset --hard HEAD"; # 取り返しのつかないことをしてしまった……!
      rhh1 = "reset --hard HEAD~";
      rhh2 = "reset --hard HEAD~~";
      rhh3 = "reset --hard HEAD~~~";
      rhh4 = "reset --hard HEAD~~~~";
      rhh5 = "reset --hard HEAD~~~~~";
      di = "diff";
      dm = "diff master"; # masterとのdiff
      dw = "diff --color-words"; # 単語単位でいろつけてdiff
      dc = "diff --cached"; # addされているものとのdiff
      ds = "diff --staged"; # 同上(1.6.1移行)
      d1 = "diff HEAD~"; # HEADから1つ前とdiff
      d2 = "diff HEAD~~"; # HEADから2つ前とdiff
      d3 = "diff HEAD~~~"; # HEADから3つ前とdiff
      d4 = "diff HEAD~~~~"; # HEADから4つ前とdiff
      d5 = "diff HEAD~~~~~"; # HEADから5つ前とdiff
      d10 = "diff HEAD~~~~~~~~~~"; # HEADから10前とdiff
      edit =
        "!f() { git status -s | cut -b 4- | grep -v '\\/$' | uniq ; }; $EDITOR `f`";
      add-unmerged =
        "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; git add `f`";
      delete-unmerged =
        "!f() { git ls-files --deleted | cut -f2 | sort -u ; }; git rm `f`";
      modified = ''
        !f() { git diff $1..$1\\^ --name-only | xargs sh -c '$EDITOR "$@" < /dev/tty' - ;}; f'';
      cherry-ticket-numbers = ''
        !f() { git cherry -v "$@" | cut -b 44- | awk 'match($0, /#[0-9]+/) {print substr($0, RSTART, RLENGTH)}' | sort -u ;}; f '';
      cherry-tickets = ''
        !f() { git cherry -v "$@" | cut -b 44- | awk 'match($0, /#[0-9]+/) {print substr($0, RSTART+1, RLENGTH-1)}' | sort -u | xargs git issue --oneline  ;}; f '';
      cch = ''
        !f() { git cherry -v "$@" | awk '{ if($1 == \"+\"){ color = \"green\" } if($1 == \"-\"){ color = \"red\" } cmd = "\"git show --date=short --no-notes --pretty=format:\\047%C\" color $1 \" %h %Cgreen%cd %Cblue%cn%x09%Creset%s\\047 --summary \" $2; cmd | getline t; close(cmd); print t }' ;}; f '';
      gr = "grep";
      gn = "grep -n";
      sm = "submodule";
      smupdate =
        "submodule foreach 'git checkout master; git pull origin master'";
      chpk = "cherry-pick"; # チンピク
      iss = "issue"; # my extended command
      ff = "flow feature";
      ffl = "flow feature list";
      ffs = "flow feature start";
      fff = "flow feature finish";
      ffc = "flow feature checkout";
      ffp = "flow feature publish";
      fr = "flow release";
      fh = "flow hotfix";
      fhl = "flow hotfix list";
      fhs = "flow hotfix start";
      fhf = "flow hotfix finish";
      fhp = "flow hotfix publish";
      fs = "flow support";
      upup = "pull upstream master --prune --autostash";
      updev = "pull upstream develop --prune --autostash";
      review = "!tig --reverse -w $(git branch-root)..HEAD";
      about-branch = ''
        !d() { description=$(git config branch.$1.description); if [ -n "$description" ]; then echo "$1 $description"; fi;}; f() { for branch in $(git branch); do d $branch; done; }; f'';
      desc = "branch --edit-description";
      dmb = ''
        !f() { bs=$(git branch --merged |grep -v ^\\* | grep -v staging | grep -v master | grep -v develop); if [ -z "$bs" ]; then echo "Merged branch does not exist."; exit; fi; echo "$bs"; read -p "Delete above branches? (y/N): " yn; case "$yn" in [yY]*) git branch -d $bs;; *) echo "abort." ; exit ;; esac }; f'';
      pr =
        "!f() { git fetch -fu \${2:-$(git remote |grep ^pr || echo origin)} pull/$1/head && git checkout FETCH_HEAD; }; f";
      find-merge =
        "!sh -c 'commit=$0 && branch=\${1:-HEAD} && (git rev-list $commit..$branch --ancestry-path | cat -n; git rev-list $commit..$branch --first-parent | cat -n) | sort -k2 -s | uniq -f1 -d | sort -n | tail -1 | cut -f2'";
      show-merge =
        "!sh -c 'merge=$(git find-merge $0 $1) && [ -n \"$merge\" ] && git show $merge'";
      showpr =
        "!f() { git log --merges --oneline --reverse --ancestry-path $1...develop | grep 'Merge pull request #' | head -n 1; }; f";
    };
    userName = "narinari";
    userEmail = "narinari.t@gmail.com";
    delta = {
      enable = true;
      options = {
        navigate = true;
        light = false;
        syntax-theme = "Monokai Extended";
      };
    };
    extraConfig = {
      init.defaultBranch = "main";
      i18n.logOutputEncoding = "utf-8";
      color = {
        status = "auto";
        diff = "auto";
        branch = "auto";
        interactive = "auto";
        grep = "auto";
        ui = "auto";
      };
      core = {
        autocrlf = false;
        safecrlf = true;
        excludesfile = "${config.xdg.configFile."git/ignore".source}";
        quotepath = "off";
        packedGitLimit = "128m";
        packedGitWindowSize = "128m";
      };
      pack = {
        deltaCacheSize = "128m";
        packSizeLimit = "128m";
        windowMemory = "128m";
      };
      push = {
        default = "simple";
        followTags = true;
      };
      pull = {
        rebase = true;
        ff = "only";
      };
      merge = {
        ff = false;
        conflictstyle = "diff3";
      };
      http.sslVerify = false;
      rebase = {
        autosquash = true;
        autoStash = true;
      };
      secrets = {
        providers = "git secrets --aws-provider";
        patterns = [
          "[A-Z0-9]{20}"
          ''
            (\"|')?(AWS|aws|Aws)?_?(SECRET|secret|Secret)?_?(ACCESS|access|Access)?_?(KEY|key|Key)(\"|')?\\s*(:|=>|=)\\s*(\"|')?[A-Za-z0-9/\\+=]{40}(\"|')?''
          ''
            (\"|')?(AWS|aws|Aws)?_?(ACCOUNT|account|Account)_?(ID|id|Id)?(\"|')?\\s*(:|=>|=)\\s*(\"|')?[0-9]{4}\\-?[0-9]{4}\\-?[0-9]{4}(\"|')?''
          "(A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}"
        ];
        allowed =
          [ "AKIAIOSFODNN7EXAMPLE" "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" ];
      };
      ghq.root = "~/dev/src";
      url = {
        "git://github.com/ghc/packages-".insteadOf =
          "git://github.com/ghc/packages/";
        "ssh://git@github.com/C-FO/".insteadOf = "https://github.com/C-FO/";
      };
      commit.template = "${config.xdg.configFile."git/commit-template".source}";
      github.user = "narinari";
    };
    lfs.enable = true;
    ignores = [ ".direnv" "result" ];
  };
}
