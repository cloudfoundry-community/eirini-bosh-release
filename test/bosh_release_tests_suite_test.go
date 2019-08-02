package bosh_release_tests_test

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"testing"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gexec"
	v1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	_ "k8s.io/client-go/plugin/pkg/client/auth"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

var (
	kubeConfig *rest.Config
)

func TestBoshReleaseTests(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "EiriniBoshReleaseTests Suite")
}

var _ = SynchronizedBeforeSuite(func() []byte { return nil }, func([]byte) {
	kubeConfig = getKubeConfigFromEnv()
})

func getKubeConfigFromEnv() *rest.Config {
	kubeConfigPath, varSet := os.LookupEnv("KUBECONFIG")
	Expect(varSet).To(BeTrue(), "KUBECONFIG must be set with current context using service account credentials")

	bs, err := ioutil.ReadFile(kubeConfigPath)
	Expect(err).To(BeNil())

	conf, err := clientcmd.RESTConfigFromKubeConfig(bs)
	Expect(err).To(BeNil())

	return conf
}

func createTestKubeNamespace() string {
	kubeClientset, err := kubernetes.NewForConfig(kubeConfig)
	Expect(err).To(BeNil())

	testKubeNamespace := &v1.Namespace{ObjectMeta: metav1.ObjectMeta{Name: fmt.Sprintf("bosh-release-tests-%d-%d", time.Now().Unix(), GinkgoParallelNode())}}
	ns, err := kubeClientset.CoreV1().Namespaces().Create(testKubeNamespace)
	Expect(err).To(BeNil())

	return ns.Name
}

func createTestServiceAccountAndRoleBinding(kubeNamespace string) (string, string, string) {
	kubeClientset, err := kubernetes.NewForConfig(kubeConfig)
	Expect(err).To(BeNil())

	svcAccount, err := kubeClientset.CoreV1().ServiceAccounts(kubeNamespace).Create(&v1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{Name: "bosh-release-tests-service-account"},
	})
	Expect(err).To(BeNil())

	clusterRoleBinding, err := kubeClientset.RbacV1().ClusterRoleBindings().Create(&rbacv1.ClusterRoleBinding{
		ObjectMeta: metav1.ObjectMeta{Name: fmt.Sprintf("bosh-release-tests-service-account-%s-cluster-admin", kubeNamespace)},
		Subjects: []rbacv1.Subject{{
			Kind:      "ServiceAccount",
			Name:      "bosh-release-tests-service-account",
			Namespace: kubeNamespace,
		}},
		RoleRef: rbacv1.RoleRef{
			Kind: "ClusterRole",
			Name: "cluster-admin",
		},
	})
	Expect(err).To(BeNil())

	var secrets []v1.ObjectReference
	Eventually(func() []v1.ObjectReference {
		s, err := kubeClientset.CoreV1().ServiceAccounts(kubeNamespace).Get("bosh-release-tests-service-account", metav1.GetOptions{})
		Expect(err).To(BeNil())
		secrets = s.Secrets
		return secrets
	}).Should(HaveLen(1))
	svcAccountTokenSecretName := secrets[0].Name

	svcAccountTokenSecret, err := kubeClientset.CoreV1().Secrets(kubeNamespace).Get(svcAccountTokenSecretName, metav1.GetOptions{})
	Expect(err).To(BeNil())

	Expect(svcAccountTokenSecret.Data).To(HaveKey("token"))

	return svcAccount.Name, string(svcAccountTokenSecret.Data["token"]), clusterRoleBinding.Name
}

func deleteTestKubeNamespace(kubeNamespace string) {
	kubeClientset, err := kubernetes.NewForConfig(kubeConfig)
	Expect(err).To(BeNil())

	Expect(kubeClientset.CoreV1().Namespaces().Delete(kubeNamespace, &metav1.DeleteOptions{})).To(Succeed())
}

func deleteClusterRoleBinding(clusterRoleBindingName string) {
	kubeClientset, err := kubernetes.NewForConfig(kubeConfig)
	Expect(err).To(BeNil())

	Expect(kubeClientset.RbacV1().ClusterRoleBindings().Delete(clusterRoleBindingName, &metav1.DeleteOptions{})).To(Succeed())
}

func createVarsFile(deploymentName, namespace, serviceAccountName, serviceAccountToken string) string {
	vars := map[string]string{
		"k8s_host_url":         kubeConfig.Host,
		"k8s_node_ca":          string(kubeConfig.TLSClientConfig.CAData),
		"k8s_system_namespace": namespace,
		"k8s_service_username": serviceAccountName,
		"k8s_service_token":    serviceAccountToken,
		"deployment_name":      deploymentName,
	}

	varsJSON, err := json.Marshal(vars)
	Expect(err).To(BeNil())

	f, err := ioutil.TempFile("", "eirini-bosh-release-tests-deploy-vars-*.json")
	Expect(err).To(BeNil())

	Expect(ioutil.WriteFile(f.Name(), varsJSON, 0644)).To(Succeed())

	return f.Name()
}

func boshDeploy(deploymentName, namespace, serviceAccountName, serviceAccountToken string, opsFiles ...string) {
	deployCmd := []string{"-n", "-d", deploymentName, "deploy", "deployment.yml", "-l", createVarsFile(deploymentName, namespace, serviceAccountName, serviceAccountToken)}
	for _, opsFile := range opsFiles {
		deployCmd = append(deployCmd, "-o", opsFile)
	}

	cmd := exec.Command("bosh", deployCmd...)

	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).To(BeNil())
	Eventually(session, 20*time.Minute).Should(gexec.Exit(0))
}

func cancelAllBoshTasks(deploymentName string) {
	Eventually(func() bool {
		cmd := exec.Command("bosh", "-d", deploymentName, "tasks", "--json")
		listTasksSession, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
		Expect(err).To(BeNil())

		type BoshTasksResult struct {
			Tables []struct {
				Rows []struct {
					Description string
					Id          string
					State       string
				}
			}
		}
		boshTasksResult := &BoshTasksResult{}
		Eventually(listTasksSession).Should(gexec.Exit(0))
		err = json.Unmarshal(listTasksSession.Out.Contents(), boshTasksResult)
		Expect(err).To(BeNil())

		tasks := boshTasksResult.Tables[0].Rows

		// Report success if there are no more bosh tasks for this deployment
		if len(tasks) == 0 {
			return true
		}

		for _, task := range tasks {
			cmd := exec.Command("bosh", "-d", deploymentName, "cancel-task", task.Id)
			cancelTaskSession, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
			Expect(err).To(BeNil())
			Eventually(cancelTaskSession).Should(gexec.Exit(0))
		}

		return false
	}, 10*time.Minute, 5*time.Second).Should(BeTrue(), "Could not cancel tasks for BOSH deployment "+deploymentName+". They will need to be manually cleaned up.")
}

func boshRunErrand(deploymentName, errandName string) *gexec.Session {
	cmd := exec.Command("bosh", "-d", deploymentName, "run-errand", errandName)
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).To(BeNil())
	return session
}

func boshDeleteDeployment(deploymentName string) {
	cmd := exec.Command("bosh", "-n", "-d", deploymentName, "delete-deployment")
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).To(BeNil())
	Eventually(session, 5*time.Minute).Should(gexec.Exit(0))
}
