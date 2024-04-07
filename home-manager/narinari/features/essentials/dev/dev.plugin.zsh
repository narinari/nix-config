function goto {
	HOST=$1
	SSH="ssh -tt -q $HOST tmux 'new-session -A -D -s $HOST'"
	if [[ -n ${TMUX} ]]; then
		tmux new-window -n $HOST $SSH
	else
		$SSH
	fi
}

function open-project {
	local project dir repository session current_session

	project=$1
	ghq_root=$(ghq root)
	if [[ ${project} == "" ]]; then
		return 1
	elif [[ -d ~/repos/${project} ]]; then
		dir=~/repos/${project}
	elif [[ -d ${ghq_root}/${project} ]]; then
		dir=${ghq_root}/${project}
	else
		return 1
	fi

	if [[ -n ${TMUX} ]]; then
		repository=${dir##*/}
		session=${repository//./-}
		current_session=$(tmux list-sessions | grep 'attached' | cut -d":" -f1)

		# debug
		# echo $project
		# echo $dir
		# echo $repository
		# echo $session
		# echo $current_session

		if [[ $current_session =~ ^[0-9]+$ ]]; then
			cd $dir
			tmux rename-session $session
		else
			tmux list-sessions | cut -d":" -f1 | grep -e "^$session\$" >/dev/null
			if [[ $? != 0 ]]; then
				tmux new-session -d -c $dir -s $session
			fi
			tmux switch-client -t $session
		fi
	else
		cd $dir
	fi
}

# from: https://gist.github.com/ttdoda/6c30de9a5f2112e72486
#
# paste64 -- OSC 52 (PASTE64) を利用した端末エミュレータ経由でのクリップボード書き込み
#
# 使い方:
#   % ls | paste64
#   ls の結果をクリップボードに書き込む。
#
#   % cat hoge | nkf -s | paste64
#   ファイル hoge の内容(日本語を含む)をクリップボードに書き込む。
#   漢字コードの扱いは端末依存。
#   例えば Tera Term の場合は現状では変換をまったく行わない為、
#   事前に CP932 に変換する必要がある。
#   将来のバージョンではTera Termで変換を行うようにする予定。
#
# 注意点:
#   OSC 52でのクリップボードアクセスはセキュリティ面の懸念から、
#   デフォルトでは無効にしている端末が多い。
#   例えば Tera Term では、[設定]-[その他の設定]-[制御シーケンス]にある
#   "リモートからのクリップボードアクセス"で書き込みを許可する必要がある。
#   この設定を変更した場合はリモートホスト側からクリップボードへのアクセスが
#   行えるようになるため、信頼できないホストへの接続時に利用するのは危険。
#
# 参考:
#   http://doda.b.osdn.me/2011/12/15/tmux-set-clipboard/
#   http://qiita.com/kefir_/items/1f635fe66b778932e278
#   http://sanrinsha.lolipop.jp/blog/2013/01/10618.html
#
# License: CC0
#
function paste64 {
	echo -ne '\e]52;0;'
	base64 | tr -d '\012'
	echo -ne '\e\\'
}

### Function extract for common file formats ###
SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

function extract {
	if [ -z "$1" ]; then
		# display usage if no parameters given
		echo "Usage: extract <path/file_name>.<zip|rar|bz2|gz|tar|tbz2|tgz|Z|7z|xz|ex|tar.bz2|tar.gz|tar.xz>"
		echo "       extract <path/file_name_1.ext> [path/file_name_2.ext] [path/file_name_3.ext]"
	else
		for n in "$@"; do
			if [ -f "$n" ]; then
				case "${n%,}" in
				*.cbt | *.tar.bz2 | *.tar.gz | *.tar.xz | *.tbz2 | *.tgz | *.txz | *.tar)
					tar xvf "$n"
					;;
				*.lzma) unlzma ./"$n" ;;
				*.bz2) bunzip2 ./"$n" ;;
				*.cbr | *.rar) unrar x -ad ./"$n" ;;
				*.gz) gunzip ./"$n" ;;
				*.cbz | *.epub | *.zip) unzip ./"$n" ;;
				*.z) uncompress ./"$n" ;;
				*.7z | *.arj | *.cab | *.cb7 | *.chm | *.deb | *.dmg | *.iso | *.lzh | *.msi | *.pkg | *.rpm | *.udf | *.wim | *.xar)
					7z x ./"$n"
					;;
				*.xz) unxz ./"$n" ;;
				*.exe) cabextract ./"$n" ;;
				*.cpio) cpio -id <./"$n" ;;
				*.cba | *.ace) unace x ./"$n" ;;
				*)
					echo "extract: '$n' - unknown archive method"
					return 1
					;;
				esac
			else
				echo "'$n' - file does not exist"
				return 1
			fi
		done
	fi
}

IFS=$SAVEIFS
