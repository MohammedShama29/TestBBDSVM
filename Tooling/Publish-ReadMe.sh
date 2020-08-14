#!/bin/bash -e
####################################################
# Version: 1.0
####################################################

ARGUMENT_LIST=(
    "ReleaseRequestedFor"
    "BranchName"
    "uGit"
    "pGit"
    "buildingBlock"
)

opts=$(getopt \
    --longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
    --name "$(basename "$0")" \
    --options "" \
    -- "$@"
)

eval set --$opts

while [[ $# -gt 0 ]]; do
    case $1 in
      --ReleaseRequestedFor)
        ReleaseRequestedFor=$2
        shift 2
        ;;
      --BranchName)
        BranchName=$2
        shift 2
        ;;
      --uGit)
        uGit=$2
        shift 2
        ;;
      --pGit)
        pGit=$2
        shift 2
        ;;
      --buildingBlock)
        buildingBlock=$2
        shift 2
        ;;
      *)
        break
        ;;
  esac  
done

# Validating needed programs
[[ $( which git) ]] || exit 101
[[ $( which curl) ]] || exit 102
[[ $( which python) ]] || exit 103

#Get my building block name
echo "Git is present proceed"
echo "Curl is present proceed"
echo "Python is present proceed"

echo "Installing python requests module"
python -m pip install requests --user --force

echo "Validating Variables"
[[ "$ReleaseRequestedFor" ]] || exit 104
[[ "$BranchName" ]] || exit 108
[[ "$uGit" ]] || exit 105
[[ "$pGit" ]] || exit 106
[[ "$buildingBlock" ]] || exit 107

if [ $BranchName == "master" ]
then
  bbVersion="NONCERTIFIED"
else
  bbVersion=${BranchName//"version/"/""}
  bbVersion=${bbVersion//"feature/"/""}
  bbVersion=${bbVersion//"bugfix/"/""}
fi

echo "Requested for: $ReleaseRequestedFor"
echo "BB Version: $bbVersion"

echo "Cloning Building Block Wiki Project"
git clone https://${uGit}:${pGit}@eysbp.visualstudio.com/CTP%20-%20Building%20Blocks/_git/Building-Blocks.wiki && cd Building-Blocks.wiki/Building-Block-Readme-Files
git config --global user.email $(echo "$ReleaseRequestedFor" | sed 's/ /./g')@gds.ey.com
git config --global user.name "$ReleaseRequestedFor"

var_resourceGroupName=$(echo $buildingBlock | sed 's/-/%2D/g')

if [ -d ${var_resourceGroupName} ]
then
  if [ -f ${var_resourceGroupName}/${bbVersion}.md ]
  then
    echo "Deleting existing ReadMe file"
	  rm ./${var_resourceGroupName}/${bbVersion}.md
  fi
else
  mkdir -p ./${var_resourceGroupName}
fi

echo "Copying ReadMe files for each version"
cp ../../ReadMe/${buildingBlock}/${bbVersion}/README.md ./${var_resourceGroupName}/${bbVersion}.md

echo "Adding New ReadMe Files To Wiki"
git add -A
git commit -m "Update ReadMe file for $buildingBlock version $bbVersion"
git push
wait $!