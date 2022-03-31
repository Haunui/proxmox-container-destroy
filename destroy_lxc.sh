#!/bin/bash

print_help() {
cat << EOF
USAGE
        $0 --node-ip <node-ip> [--node-name <node-name>] --username <username> --password <password> --ct-id <container_id>

DESCRIPTION
        Détruire le conteneur <container_id> sur le node <node_name>

        --node-ip
                IP du noeud

        --node-name (optionnel) [defaut: proxmox]
                Nom du noeud

        --username, -u
                Nom de l'utilisateur qui sera pris pour créer le conteneur

        --password, -p
                Mot de passe de l'utilisateur qui sera pris pour créer le conteneur

        --ct-id
                ID du conteneur
EOF

}

if [ $# -eq 0 ]; then
        print_help
        exit 1
fi


while [ $# -gt 0 ]; do
        key=$1

        case $key in
                --node-ip)
                        NODE_IP=$2
                        shift
                        shift
                        ;;
                --node-name)
                        NODE_NAME=$2
                        shift
                        shift
                        ;;
                --username|-u)
                        USERNAME=$2
                        shift
                        shift
                        ;;
                --password|-p)
                        PASSWORD=$2
                        shift
                        shift
                        ;;
                --ct-id)
                        CONTAINER_ID=$2
                        shift
                        shift
                        ;;
		*)
			UNKNOWN_FLAG=$1
			break
        esac
done

###CHECK UNKNWON FLAG

if [ ! -z "$UNKNOWN_FLAG" ]; then
	echo "Flag '$UNKNOWN_FLAG' inconnu"
	exit 1
fi



### CHECK CONNECTION INFOS

if [ -z "$USERNAME" ]; then
        echo "Vous devez spécifier un utilisateur"
        exit 1
fi

if [ -z "$PASSWORD" ]; then
        echo "Vous devez spécifier un mot de passe"
        exit 1
fi

if [ -z "$NODE_IP" ]; then
        echo "Vous devez spécifier l'adresse du noeud au quel le programme se connectera"
        exit 1
fi

if [ -z "$NODE_NAME" ]; then
        NODE_NAME=proxmox
fi


### CHECK CONTAINER INFOS

if [ -z "$CONTAINER_ID" ]; then
        echo "Vous devez spécifier l'ID du conteneur"
        exit 1
fi

if ! [[ "$CONTAINER_ID" =~ ^[0-9]+$ ]]; then
	echo "L'ID du conteneur doit être un nombre"
	exit 1
fi

##### GET COOKIE

curl --silent --insecure --data "username=$USERNAME&password=$PASSWORD" \
 https://$NODE_IP:8006/api2/json/access/ticket\
| jq --raw-output '.data.ticket' | sed 's/^/PVEAuthCookie=/' > cookie


##### GET CSRF TOKEN

curl --silent --insecure --data "username=$USERNAME&password=$PASSWORD" https://$NODE_IP:8006/api2/json/access/ticket | jq --raw-output '.data.CSRFPreventionToken' | sed 's/^/CSRFPreventionToken:/' > csrftoken


##### DESTROY LXC

# STOP CONTAINER
result=$(curl --silent --insecure --cookie "$(<cookie)" --header "$(<csrftoken)" -X POST https://$NODE_IP:8006/api2/json/nodes/$NODE_NAME/lxc/${CONTAINER_ID}/status/stop)

# GET CONTAINER STATUS FUNCTION
get_server_status() {
  result=$(curl --silent --insecure --cookie "$(<cookie)" --header "$(<csrftoken)" -X GET https://$1:8006/api2/json/nodes/$2/lxc/$3/status/current)

  server_status=$(echo "$result" | jq .data.status | sed 's/"//g')
  echo "$server_status"
}

# WAIT FOR CONTAINER TO STOP
echo "En attente de l'arrêt du conteneur ($CONTAINER_ID) .."
while [ "$(get_server_status $NODE_IP $NODE_NAME $CONTAINER_ID)" = "running" ]; do
  sleep 2
done

# DESTROY CONTAINER
echo "Destruction du conteneur ($CONTAINER_ID) .."
result=$(curl --silent --insecure --cookie "$(<cookie)" --header "$(<csrftoken)" -X DELETE https://$NODE_IP:8006/api2/json/nodes/$NODE_NAME/lxc/$CONTAINER_ID)

rm -f csrftoken cookie &> /dev/null
rm -rf tmp &> /dev/null
