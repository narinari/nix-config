_:

{
  xdg.configFile."fcitx5/profile".text = ''
    [Groups/0]
    Name=Default
    Default Layout=us
    DefaultIM=keyboard-us

    [Groups/0/Items/0]
    Name=keyboard-us
    Layout=

    [Groups/0/Items/1]
    Name=skk
    Layout=

    [GroupOrder]
    0=Default
  '';

  xdg.configFile."fcitx5/conf/skk.conf".text = ''
    Rule=default
    PunctuationStyle=Japanese
    InitialInputMode=Hiragana
    PageSize=7
    Candidate Layout=Vertical
    EggLikeNewLine=True
    ShowAnnotation=True
    CandidateChooseKey="Qwerty Center Row (a,s,d,...)"
    NTriggersToShowCandWin=4

    [CandidatesPageUpKey]
    0=Page_Up

    [CandidatesPageDownKey]
    0=Next

    [CursorUp]
    0=Up

    [CursorDown]
    0=Down
  '';
}
