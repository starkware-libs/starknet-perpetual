#!/bin/bash

helpFunction()
{
   echo ""
   echo "Usage: $0 -a Account name -u RpcUrl -c contract -p package"
   exit 1
}

while getopts "a:u:c:p:" opt
do
   case "$opt" in
      a ) account="$OPTARG" ;;
      u ) url="$OPTARG" ;;
      c ) contract="$OPTARG" ;;
      p ) package="$OPTARG" ;;
      ? ) helpFunction ;;
   esac
done

if [ -z "$account" ] || [ -z "$url" ] || [ -z "$contract" ] || [ -z "$package" ]; then
   echo "All parameters are required." >&2
   helpFunction
fi

declare_contract_class() {
   local account="$1"
   local url="$2"
   local contract="$3"
   local package="$4"

   echo "Computing local class hash for $contract..." >&2

   local CLASS_HASH
   CLASS_HASH=$(sncast --account "$account" utils class-hash -c "$contract" --package "$package" \
                | grep -oE '0x[0-9a-fA-F]{64}' | head -n 1)

   if [ -z "$CLASS_HASH" ]; then
      echo "ERROR: Failed to compute local class hash." >&2
      exit 1
   fi

   echo "Local class hash: $CLASS_HASH" >&2
   echo "Declaring class on chain (URL: $url)..." >&2

   local declare_output
   declare_output=$(sncast --account "$account" declare -u "$url" -c "$contract" --package "$package" 2>&1)
   local declare_status=$?

   echo "$declare_output" >&2

   echo "$declare_output" >> log.txt
   echo "----------------------------------------" >> log.txt

   if [ $declare_status -ne 0 ]; then
      echo "WARNING: Declaration command exited with status $declare_status (e.g., class may already be declared)." >&2
      echo "The local class hash is still valid and returned below." >&2
   else
      echo "Declaration command completed successfully." >&2
   fi
   echo "$CLASS_HASH"
}

# Call the function with the parsed parameters
declare_contract_class "$account" "$url" "$contract" "$package"