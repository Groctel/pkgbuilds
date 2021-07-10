#!/bin/bash

declare aur=0
declare setup=1
declare pkg=""
declare user=""
declare rootdir=""

installPackage ()
{
	cd "$pkg" || exit 1

	su "$user" -c "makepkg -s" || exit 1
	pacman -U --noconfirm ./*.zst || exit 1

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
	chmod 777 "$pkg" # Not recommended but the image is killed on exit
	cd "$pkg" || exit 1

	local -r srcinfo="$(su "$user" -c "makepkg --printsrcinfo")"
	local -r depends="$(echo "$srcinfo" | grep 'depends' | sed 's/.*= \|:.*//g')"
	local -a to_install=()

	for dep in $depends
	do
		echo "==> Finding $dep origin..."

		if pacman -Sp "$dep" 1>/dev/null 2>&1
		then
			echo "  -> Found in pacman repositories"
			to_install+=("$dep")
		else
			# If we have the pkgbuild in the repository
			local dircount
			dircount="$(find "$rootdir" -maxdepth 1 -name "*$dep" | wc -l)"

			if [[ $dircount != 0 ]]
			then
				echo "  -> Found in our repository"
				echo ":: Switching installation to $dep"

				cd "$rootdir/$dep" || exit 1
				$0 -nosetup pkg="$dep" user="$user"
				cd - || exit 1

				echo ":: Returned from installing $dep, back to $pkg"
			else
				echo "  -> Found in the AUR"
				echo ":: Switching installation to $dep"
				$0 -nosetup -aur pkg="$dep" user="$user"
				echo ":: Returned from installing $dep, back to $pkg"
			fi
		fi
	done

	echo ":: Finished finding dependencies for $pkg, installing..."
	pacman -S --noconfirm --asdeps ${to_install[*]/,/} || exit 1
	cd - || exit 1
}

installFromRepo ()
{
	cd "$(echo "$0" | sed 's/\/[^\/]\+//')" || exit 1
	declare -g rootdir
	rootdir="$(pwd)"

	installDependencies
	installPackage "$pkg"
}

setupContainer ()
{
	groupadd -f arch
	useradd -m -G arch -s /bin/bash manim
	pacman -Sy

	local -a dependencies=()

	pacman -Q git  1>/dev/null 2>&1 || dependencies+=('git')
	pacman -Q sudo 1>/dev/null 2>&1 || dependencies+=('sudo')

	pacman -Syuu --noconfirm ${dependencies[*]/,/}
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

		echo ":: Found argument: name = $name --- value = $value"
		shift
	done
}

main ()
{
	parseArgs "$@"
	[[ $setup -eq 1 ]] && setupContainer

	echo ":: Starting installation process for $pkg..."

	if [[ $aur -eq 1 ]]
	then
		installFromAUR
	else
		installFromRepo
	fi

	pacman --noconfirm -Rcns $(pacman -Qtdq)

	echo ":: Successfully finished $pkg installation!"
}

main "$@"
