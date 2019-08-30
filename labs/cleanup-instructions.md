<a id="markdown-clean-up-4" name="clean-up-4"></a>

# Lab 4 Clean up
To clean up the test application run:

~~~sh
argocd app delete rhte-simple-app
~~~

<a id="markdown-clean-up-6" name="clean-up-6"></a>

# Lab 6 Clean Up
To clean up the MongoDB Application run:

~~~sh
argocd app delete cluster1-mongo
argocd app delete cluster2-mongo
argocd app delete cluster3-mongo
~~~

<a id="markdown-clean-up-7" name="clean-up-7"></a>

# Lab 7 Clean Up
To clean up the HAProxy LB and Pacman Application run:

~~~sh
namespace-cleanup -n haproxy-lb
argocd app delete cluster1-pacman
argocd app delete cluster2-pacman
argocd app delete cluster3-pacman
~~~