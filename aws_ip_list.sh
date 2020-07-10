:

echo ""
echo "Name      PublicIP        PrivateIP"
echo "----      --------        ---------"
echo ""
aws ec2 describe-instances --query "Reservations[*].Instances[*].[Tags[0].Value,PublicIpAddress,PrivateIpAddress]" --output=text
