#!/bin/bash

helpFunction()
{
   echo ""
   echo "Usage: $0 -a Account name -u RpcUrl -c contract -n name -h hash"
   exit 1 # Exit script after printing help
}

while getopts "a:u:c:n:h:" opt
do
   case "$opt" in
      a ) account="$OPTARG" ;;
      u ) url="$OPTARG" ;;
      c ) contract="$OPTARG" ;;
      n ) name="$OPTARG" ;;
      h ) hash="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

if [ -z "$account" ]
then
   echo "Account is missing pass -a";
   helpFunction
fi
if [ -z "$url" ]
then
   echo "Url is missing pass -u";
   helpFunction
fi
if [ -z "$contract" ]
then
   echo "Contract is missing pass -c";
   helpFunction
fi
if [ -z "name" ]
then
   echo "Name is missing pass -n";
   helpFunction
fi
if [ -z "hash" ]
then
   echo "Hash is missing pass -h";
   helpFunction
fi

NAME_HASH=$(echo 0x$(echo -n $name | xxd -p ))
echo $name
echo $NAME_HASH $hash
# sleep 10
# sncast --account=$account invoke -u $url --contract-address $contract --function register_external_component --calldata  $NAME_HASH $hash
# echo activate $name
# sleep 10
# sncast --account=$account invoke -u $url --contract-address $contract --function activate_external_component --calldata  $NAME_HASH $hash