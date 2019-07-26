<a id="markdown-clean-up-4" name="clean-up-4"></a>

# Lab 4 Clean up
To clean up the test application run:

~~~sh
oc delete -R -f sample-app/
for cluster in cluster1 cluster2; do
  oc --context=${cluster} -n test-namespace delete route test-service
done
~~~

To clean up the `test-namespace` namespace run:

~~~sh
for cluster in cluster1 cluster2; do
  oc --context=${cluster} delete namespace test-namespace
done
~~~

<a id="markdown-clean-up-5" name="clean-up-5"></a>

# Lab 5 Clean Up

TBD

<a id="markdown-clean-up-6" name="clean-up-6"></a>

# Lab 5 Clean Up

TBD
