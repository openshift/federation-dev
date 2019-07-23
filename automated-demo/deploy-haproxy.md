# Deploy HAProxy for Pacman

1. Copy and modify the configmap definition [here](./yaml-resources/haproxy/haproxy.tmpl)
~~~sh
cp yaml-resources/haproxy/haproxy.tmpl yaml-resources/haproxy/haproxy
~~~   

Make the following changes to the newly created haproxy file.
  ```
  backend app
    balance roundrobin
    option httpchk GET / HTTP/1.1\r\nHost:\ pacman.example.com
    mode http 
      server west2 pacman.apps.west-2.example.com:80 check
      server east pacman.apps.east-1.example.com:80 check
      server ohio pacman.apps.east-2.example.com:80 check
  ```
2. `pacman.example.com` should be changed for your pacman dns record pointing to the haproxy deployments
3. The three different servers from the backend should be anything to resolve to each of your cluster OCP Routers
4. Create a namespace/use an existing one and create the configmap from our definition

  ```sh
  oc -n <your_namespace> create configmap haproxy --from-file=yaml-resources/haproxy/haproxy
  ```
5. Create the deployment and the service for haproxy

  ```sh
  oc -n <your_namespace> create -f yaml-resources/haproxy/haproxy-service.yaml
  oc -n <your_namespace> create -f yaml-resources/haproxy/haproxy-deployment.yaml
  ```

# AWS Route53 Configuration

This demonstration uses Route53 for DNS. The first step is to look up the value of the load balancer service and then assign a DNS A record.

~~~sh
oc -n <your_namespace> get svc haproxy-lb-service
NAME         TYPE           CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)        AGE
haproxy-lb-service   LoadBalancer   172.31.161.224   ae294119d6d0d11e9b8b10e1ce99fb1b-1020848795.us-east-1.elb.amazonaws.com   80:31587/TCP   86m
~~~

The next step is to provide the load balancer `EXTERNAL-IP` to a the DNS zone to allow for routing.

NOTE: The A record will point to the publicly accessible address for the *pacman* application.

Enter the value of the publicly accessible address and use an Alias to point to the `haproxy-lb-service` load balancer `ELB`.

![Route53](../images/route53.png)
