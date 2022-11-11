#Remplace apiVersion extensions/v1beta1 for apps/v1 for compatibility 
# Add selector name mongo
cat > deployments/mongo-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    name: mongo
  name: mongo
spec:
  replicas: 0
  selector:
    matchLabels:
      name: mongo
  template:
    metadata:
      labels:
        name: mongo
    spec:
      containers:
      - image: mongo
        name: mongo
        ports:
        - name: mongo
          containerPort: 27017
        volumeMounts:
          - name: mongo-db
            mountPath: /data/db
      volumes:
        - name: mongo-db
          persistentVolumeClaim:
            claimName: mongo-storage
EOF


#Remplace apiVersion extensions/v1beta1 for apps/v1 for compatibility
# Add selector name pacman
cat > deployments/pacman-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    name: pacman
  name: pacman
spec:
  replicas: 0
  selector:
    matchLabels:
      name: pacman
  template:
    metadata:
      labels:
        name: pacman
    spec:
      containers:
      - image: quay.io/ifont/pacman-nodejs-app:latest
        name: pacman
        ports:
        - containerPort: 8080
          name: http-server
EOF
