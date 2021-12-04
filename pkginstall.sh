#!/usr/bin/env bash

declare aur=0
declare setup=1
declare pkg=""
declare user=""
declare rootdir=""

installPackage ()
{
	echo "[$pkg] ==> Starting installation..."
	cd "$rootdir" || exit 1
	cd "$pkg" || exit 1

	echo "[$pkg]  -> Making package..."
	su "$user" -c "makepkg -s" || exit 1

	echo "[$pkg]  -> Installing package..."
	pacman -U --needed --noconfirm ./*.zst || exit 1

	cd - || exit 1
}

installFromAUR ()
{
	git clone "https://aur.archlinux.org/$pkg"
	installDependencies
	installPackage
}

installDependencies ()
{
	cd "$rootdir" || exit 1
	chmod 777 "$pkg" # Not recommended but the image is killed on exit
	cd "$pkg" || exit 1

	local -r srcinfo="$(su "$user" -c "makepkg --printsrcinfo")"
	local -r depends="$(echo "$srcinfo" | grep 'depends' | sed 's/.*= \|:.*//g')"
	local -a to_install=()

	for dep in $depends
	do
		echo "[$pkg] ==> Finding origin for $dep..."

		if pacman -Sp "$dep" 1>/dev/null 2>&1
		then
			echo "[$pkg]  -> Found in pacman repositories"
			to_install+=("$dep")
		else
			# If we have the pkgbuild in the repository
			local dircount
			dircount="$(find "$rootdir" -maxdepth 1 -name "*$dep" | wc -l)"

			if [[ $dircount != 0 ]]
			then
				echo "[$pkg]  -> Found in our repository"
				echo "[$pkg]:: Switching installation to $dep"

				cd "$rootdir/$dep" || exit 1
				$0 -nosetup pkg="$dep" user="$user"
				cd - || exit 1

				echo "[$pkg]:: Returned from installing $dep"
			else
				echo "[$pkg]  -> Found in the AUR"
				echo "[$pkg]:: Switching installation to $dep"
				$0 -nosetup -aur pkg="$dep" user="$user"
				echo "[$pkg]:: Returned from installing $dep"
			fi
		fi
	done

	if [[ "${#to_install[@]}" -ne 0 ]]
	then
		echo "[$pkg]:: Finished finding dependencies. Starting installation..."

		# shellcheck disable=SC2086
		# shellcheck disable=SC2048
		pacman -S --needed --noconfirm --asdeps ${to_install[*]/,/} || exit 1
	else
		echo "[$pkg]:: No dependencies were found."
	fi

	cd - || exit 1
}

installFromRepo ()
{
	cd "$(echo "$0" | sed 's/\/[^\/]\+//')" || exit 1
	declare -g rootdir
	rootdir="$(pwd)"

	installDependencies
	installPackage
}

setupContainer ()
{
	groupadd -f arch
	useradd -m -G arch -s /bin/bash "$user"
	pacman -Sy

	local -a dependencies=()

	pacman -Q git  1>/dev/null 2>&1 || dependencies+=('git')
	pacman -Q sudo 1>/dev/null 2>&1 || dependencies+=('sudo')

	# shellcheck disable=SC2086
	# shellcheck disable=SC2048
	pacman -Syuu --needed --noconfirm ${dependencies[*]/,/}
}

parseArgs ()
{
	while [[ $# -gt 0 ]]
	do
		local arg="$1"
		local name="${arg/=*/}"
		local value="${arg/*=/}"

		case "$name"
		in
		-aur)
			declare -g aur=1
		;;
		-nosetup)
			declare -g setup=0
		;;
		pkg)
			declare -g pkg="$value"
		;;
		user)
			declare -g user="$value"
		;;
		esac

		echo "[pkg]:: Found argument: name = $name --- value = $value"
		shift
	done
}

main ()
{
	parseArgs "$@"
	[[ $setup -eq 1 ]] && setupContainer

	echo "[pkg]:: Starting installation process..."

	if [[ $aur -eq 1 ]]
	then
		installFromAUR
	else
		installFromRepo
	fi

	# shellcheck disable=SC2046
	pacman --noconfirm -Rcns $(pacman -Qtdq)

	echo "[pkg]:: Successfully finished installation!"
}

main "$@"
