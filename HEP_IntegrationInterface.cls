/**
* HEP_IntegrationInterface --- Interface declaring the method which all the integration classes
* 							   need to implement
* @author    Sachin Agarwal
*/
public interface HEP_IntegrationInterface {
	
	/**
    * performTransaction --- Method that will carry out the actual integration business logic
    * @author    Sachin Agarwal
    */
	void performTransaction(HEP_InterfaceTxnResponse objTxnResponse);
}