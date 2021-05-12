
helm repo add bitnami https://charts.bitnami.com/bitnami

helm install postgres bitnami/postgresql \
  --set service.type=LoadBalancer \
    
export POSTGRES_PASSWORD=$(kubectl get secret --namespace default postgres-postgresql -o jsonpath="{.data.postgresql-password}" | base64 --decode)

kubectl run postgres-postgresql-client --rm --tty -i --restart='Never' --namespace default --image docker.io/bitnami/postgresql:11.11.0-debian-10-r86 --env="PGPASSWORD=$POSTGRES_PASSWORD" --command -- psql --host postgres-postgresql -U postgres -d postgres -p 5432

export SERVICE_IP=$(kubectl get svc --namespace default postgres-postgresql --template "{{ range (index .status.loadBalancer.ingress 0) }}{{.}}{{ end }}")
    
PGPASSWORD="$POSTGRES_PASSWORD" psql --host $SERVICE_IP --port 5432 -U postgres -d postgres

CREATE ROLE ro NOINHERIT;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "ro";
\q

vault secrets enable database

vault write database/config/postgresql \
     plugin_name=postgresql-database-plugin \
     connection_url="postgresql://{{username}}:{{password}}@$SERVICE_IP:5432/postgres?sslmode=disable" \
     allowed_roles=readonly \
     username="postgres" \
     password="$POSTGRES_PASSWORD"

tee readonly.sql <<EOF
CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' INHERIT;
GRANT ro TO "{{name}}";
EOF

vault write database/roles/readonly \
      db_name=postgresql \
      creation_statements=@readonly.sql \
      default_ttl=2m \
      max_ttl=2m


PGPASSWORD="$POSTGRES_PASSWORD" psql --host $SERVICE_IP --port 5432 -U postgres -d postgres

SELECT usename, valuntil FROM pg_user;