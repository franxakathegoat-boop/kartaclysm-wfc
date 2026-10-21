FROM golang:1.25-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/wwfc .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates gettext-base && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /out/wwfc /app/wwfc
COPY game_list.tsv motd.txt schema.sql /app/
COPY deploy/config.xml.tmpl deploy/entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]
