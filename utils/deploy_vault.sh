#!/bin/bash

decimal_to_hex() {
    if [[ $# -eq 0 ]]; then
        printf "0x0"
    fi

    printf "0x%x" "$1"
}

str_to_felt_array() {
    echo "0x0" "$(echo 0x$(echo -n $1 | xxd -p ))"  "$(decimal_to_hex ${#1})"
}

helpFunction()
{
   echo ""
   echo "Usage: $0 -a Account name -u RpcUrl -c contract -p package"
   exit 1 # Exit script after printing help
}

while getopts "a:u:" opt
do
   case "$opt" in
      a ) account="$OPTARG" ;;
      u ) url="$OPTARG" ;;
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


NAME=$(str_to_felt_array "XVS")
SYMBOL=$(str_to_felt_array "XVS")
COLLATERAL_CONTRACT_ADDRESS="0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8"
PERPS_CONTRACT="0x062DA0780fAe50d68CECAa5A051606dc21217BA290969b302DB4DD99D2E9b470"
OWNING_POSITION="0x7"
RECIPIENT="0x785932b867b6a21dfd64367edd181c1cfa83fa7ce942d005857cd5935049d58"
INITIAL_PRICE=$(decimal_to_hex 1078589)
HASH=0x07b0175546225b6f64bb455ad64d59b29e35b2217f1435e66c62c3cab554db20
echo Hash is $HASH
ADDRESS=$(sncast --account $account  deploy -u $url --class-hash=$HASH  --constructor-calldata $NAME $SYMBOL $COLLATERAL_CONTRACT_ADDRESS $PERPS_CONTRACT $OWNING_POSITION $RECIPIENT $INITIAL_PRICE | grep -oE '0x[0-9a-f]{64}'| sed -n '1p')
echo $ADDRESS