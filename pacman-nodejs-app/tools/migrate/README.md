# Kubernetes Migration Tool (KMT)

This `kmt` tool is a proof-of-concept to help demonstrate an application migration use-case. The application of choice is Pac-Man.
It can be used to migrate from cluster A (SOURCE) to cluster B (DESTINATION).

## Usage

```bash
./kmt.sh: [OPTIONS] [-f|--from-context CONTEXT] [-t|--to-context CONTEXT] [-n|--namespace NAMESPACE] [-z|--zone ZONE_NAME] [-d|--dns DNS_NAME]
  Optional Arguments:
    -h, --help             Display this usage
    -v, --verbose          Increase verbosity for debugging
  Required arguments:
    -f, --from-context     source CONTEXT to migrate application
    -t, --to-context       destination CONTEXT to migrate application
    -n, --namespace        namespace containing Kubernetes resources to migrate
    -z, --zone             name of zone for your Google Cloud DNS e.g. zonename
    -d, --dns              domain name used for your Google Cloud DNS zone e.g. 'example.com.'
```

## Examples

Short options:

```bash
./kmt.sh -v -f gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 \
            -t gke_${GCP_PROJECT}_us-central1-b_gce-us-central1 \
            -n pacman \
            -z ZONENAME \
            -d example.com.
```

Long options:

```bash
./kmt.sh --verbose --from-context gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 \
                   --to-context gke_${GCP_PROJECT}_us-central1-b_gce-us-central1 \
                   --namespace pacman \
                   --zone ZONENAME \
                   --dns example.com.
```

