# tfm-dbre

## Requirements:
* Cloud SDK
* Terraform

## Google Cloud
Install the [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) based on guideline provided on the website.
### Interacting with Google Cloud as the right user:
* Run  `gcloud auth list` to list logged-in users and `gcloud config set account`, if needed, to switch to the current account:
```
$ gcloud auth list

   Credentialed Accounts

ACTIVE  ACCOUNT

       example@example.com

*     example@other-example.com

$ gcloud config set account example@example.com

Updated property [core/account].
```
If the right account is not listed, run `gcloud auth login`. This will open a browser window and allow you to log in to your account of choice.

### Create a new GCP project:
```
$ gcloud projects create ${project_ID} \

    --name "${project_name}" \

    --set-as-default
```

### Enable APIs for the project:
```
gcloud services enable servicenetworking.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable appengine.googleapis.com
gcloud services enable iam.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable cloudscheduler.googleapis.com
```

### Setup GCP service account:
To create a service account, run:
```
$ gcloud iam service-accounts create ${service_account_ID} \

    --display-name ${display_name}

Created service account ${service_account_ID}.

$ gcloud iam service-accounts list

DISPLAY NAME      EMAIL                                             DISABLED

Tutorial Account  ${service_account_ID}@${project_ID}.iam.gserviceaccount.com False
```

### Grant permissions based on user, etc `OWNER` role:
```
$ gcloud projects add-iam-policy-binding ${project_ID} --role=roles/owner \

--member=serviceAccount:${service_account_ID}@${project_ID}.iam.gserviceaccount.com
```

### Create and export secret key for the project:
Generate secret key file:
```
$ gcloud iam service-accounts keys create account-key.json \  

--iam-account=${service_account_ID}@${project_ID}.iam.gserviceaccount.com
```
NOTE: Keep this file safe, and never commit it to SCM. If leaked, it can provide access to your entire GCP project. 

To use the key for Terraform projects, run:
```
$ export GOOGLE_APPLICATION_CREDENTIALS=account-key.json
```

## Terraform
Install [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/gcp-get-started) based on guideline provided on the website.

Start by running the `plan` command to see how Terraform plans to provision the resources you’ve described:
```
$ terraform plan
```
After that, run the `apply` command to provision the infrastructure.
```
$ terraform apply
```

VIOLA! The infrastructure was provisioned

## Cleaning up
To clean up everthing done, run the `destroy` command to destroy all the resources created:
```
$ terraform destory
```

## End
That's all about how to provision the GCP Resources with Terraform.